import EventKit
import Foundation
import SwiftUI

/// A rendered event line with its calendar color for display
struct EventLineInfo: Equatable {
    let text: String
    let calendarColor: Color
}

@MainActor
@Observable
final class CalendarStore {
    /// Full interleaved text per date (events + journal mixed, in user's order)
    private(set) var dayTexts: [Date: String] = [:]

    /// Color lookup for event lines: maps (title, hour, minute) → Color from EventKit
    private(set) var eventColorMap: [Date: [EventColorKey: Color]] = [:]

    /// EventKit-only events not yet in the user's text (added from other apps)
    private(set) var unmatchedEventLines: [Date: [EventLineInfo]] = [:]

    /// Whether EventKit access has been granted
    private(set) var hasCalendarAccess = false

    /// Sync status for UI feedback
    enum SyncStatus: Equatable {
        case idle
        case saving
        case syncing
        case error(String)
    }
    var syncStatus: SyncStatus = .idle

    private(set) var eventKitManager: EventKitManager?
    private var fileStore: FileStore?
    private var coalescer: ChangeCoalescer?
    private(set) var calendarSettings: CalendarSettings?

    /// Debounce EventKit sync to avoid re-syncing on every keystroke
    private var syncTask: Task<Void, Never>?

    /// LRU tracking for dayTexts cache eviction
    private var accessOrder: [Date] = []
    private let maxCachedDays = 180

    /// Cached parsed event keys to avoid re-parsing unchanged text
    private var parsedKeyCache: [Date: (hash: Int, keys: Set<EventColorKey>)] = [:]

    /// Journal text per date (only freeform text, not events) — used during parsing
    private var journals: [Date: String] = [:]

    init() {}

    /// Connect to persistence layers
    func configure(eventKitManager: EventKitManager, fileStore: FileStore, coalescer: ChangeCoalescer, calendarSettings: CalendarSettings = CalendarSettings()) {
        self.eventKitManager = eventKitManager
        self.fileStore = fileStore
        self.coalescer = coalescer
        self.calendarSettings = calendarSettings

        // Wire up error reporting from the coalescer
        Task {
            await coalescer.setErrorHandler { [weak self] _ in
                Task { @MainActor in
                    self?.syncStatus = .error(Strings.saveFailed)
                }
            }
        }
    }

    /// Request calendar access and load initial data
    func load() async {
        // Request EventKit access
        if let ekManager = eventKitManager {
            hasCalendarAccess = await ekManager.requestAccess()
        }

        // Load day texts from per-day files
        if let fileStore {
            do {
                let allJournals = try await fileStore.loadAllJournals()
                for (date, text) in allJournals {
                    dayTexts[date] = text
                    journals[date] = text
                }
            } catch {
                // Fresh start
            }

            // Migrate from legacy single-file format if needed
            await migrateLegacyIfNeeded()
        }
    }

    // MARK: - LRU Cache

    /// Mark a date as recently accessed and evict old entries if needed
    private func touchDate(_ date: Date) {
        accessOrder.removeAll { $0 == date }
        accessOrder.append(date)
        evictIfNeeded()
    }

    /// Evict least-recently-accessed entries when cache exceeds threshold
    private func evictIfNeeded() {
        while accessOrder.count > maxCachedDays {
            let evicted = accessOrder.removeFirst()
            dayTexts.removeValue(forKey: evicted)
            eventColorMap.removeValue(forKey: evicted)
            unmatchedEventLines.removeValue(forKey: evicted)
            journals.removeValue(forKey: evicted)
            parsedKeyCache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Reading

    /// Get the full display text for a date (interleaved events + journal in user order)
    func displayText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        touchDate(key)

        let userText = dayTexts[key] ?? ""
        let unmatched = unmatchedEventLines[key] ?? []

        if unmatched.isEmpty {
            return userText
        }

        // Append EventKit-only events (from other apps) below user's text
        var parts: [String] = []
        if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(userText)
        }
        let unmatchedText = unmatched.map(\.text).joined(separator: "\n")
        parts.append(unmatchedText)
        return parts.joined(separator: "\n")
    }

    /// Ensure day text is loaded from disk if not already cached
    func ensureLoaded(for date: Date) async {
        let key = DateFormatting.normalizeToDay(date)
        if dayTexts[key] == nil, let fileStore {
            if let text = try? await fileStore.loadJournal(for: key), !text.isEmpty {
                dayTexts[key] = text
            }
        }
    }

    /// Get the color map for a date (used by StyledTextView to color event lines)
    func colorMap(for date: Date) -> [EventColorKey: Color] {
        let key = DateFormatting.normalizeToDay(date)
        return eventColorMap[key] ?? [:]
    }

    /// Get unmatched EventKit events for a date
    func unmatchedEvents(for date: Date) -> [EventLineInfo] {
        let key = DateFormatting.normalizeToDay(date)
        return unmatchedEventLines[key] ?? []
    }

    /// Refresh event data from EventKit for a specific date.
    /// Builds the color map and identifies unmatched events.
    func refreshEvents(for date: Date) async {
        guard let ekManager = eventKitManager, hasCalendarAccess else { return }
        let key = DateFormatting.normalizeToDay(date)
        let ekEvents = await ekManager.events(for: key)
        let defaultCalId = await resolveDefaultCalendarId()
        processEventsForDate(key, ekEvents: ekEvents, defaultCalId: defaultCalId)
    }

    /// Batch refresh events for a date range using a single EventKit query.
    /// Much faster than calling refreshEvents(for:) per-date.
    func refreshEventsInRange(from start: Date, to end: Date) async {
        guard let ekManager = eventKitManager, hasCalendarAccess else { return }
        let cal = Calendar.current
        let normalizedStart = DateFormatting.normalizeToDay(start)
        guard let rangeEnd = cal.date(byAdding: .day, value: 1, to: DateFormatting.normalizeToDay(end)) else { return }

        let allEvents = await ekManager.events(from: normalizedStart, to: rangeEnd)
        let defaultCalId = await resolveDefaultCalendarId()

        // Group events by day
        var eventsByDay: [Date: [EKEvent]] = [:]
        for event in allEvents {
            let dayKey = DateFormatting.normalizeToDay(event.startDate)
            eventsByDay[dayKey, default: []].append(event)
        }

        // Process each day's events
        var current = normalizedStart
        let normalizedEnd = DateFormatting.normalizeToDay(end)
        while current <= normalizedEnd {
            let dayEvents = eventsByDay[current] ?? []
            processEventsForDate(current, ekEvents: dayEvents, defaultCalId: defaultCalId)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
    }

    /// Shared logic: process EventKit events for a single date, building color map + unmatched list.
    private func processEventsForDate(_ key: Date, ekEvents: [EKEvent], defaultCalId: String?) {
        let cal = Calendar.current
        var colorMap: [EventColorKey: Color] = [:]

        for event in ekEvents {
            let color = EventKitSync.calendarColor(from: event)
            let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let colorKey = EventColorKey(
                title: event.title ?? "",
                hour: comps.hour,
                minute: comps.minute,
                isAllDay: event.isAllDay
            )
            colorMap[colorKey] = color
        }

        eventColorMap[key] = colorMap

        // Find EventKit events not represented in user's text (with caching)
        let userText = dayTexts[key] ?? ""
        let textHash = userText.hashValue
        let userEventKeys: Set<EventColorKey>

        if let cached = parsedKeyCache[key], cached.hash == textHash {
            userEventKeys = cached.keys
        } else {
            let userLines = userText.components(separatedBy: "\n")
            var keys = Set<EventColorKey>()
            for line in userLines {
                let parsed = LineParser.parse(line)
                switch parsed {
                case .event(let time, _, let title, _, _):
                    keys.insert(EventColorKey(
                        title: title,
                        hour: time.hour,
                        minute: time.minute,
                        isAllDay: false
                    ))
                case .allDay(let title, _, _):
                    keys.insert(EventColorKey(
                        title: title,
                        hour: nil,
                        minute: nil,
                        isAllDay: true
                    ))
                default:
                    break
                }
            }
            parsedKeyCache[key] = (hash: textHash, keys: keys)
            userEventKeys = keys
        }

        var unmatched: [EventLineInfo] = []
        for event in ekEvents {
            let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let ek = EventColorKey(
                title: event.title ?? "",
                hour: comps.hour,
                minute: comps.minute,
                isAllDay: event.isAllDay
            )
            if !userEventKeys.contains(ek) {
                let line = EventKitSync.textLine(from: event, defaultCalendarId: defaultCalId)
                let color = EventKitSync.calendarColor(from: event)
                unmatched.append(EventLineInfo(text: line, calendarColor: color))
            }
        }

        unmatchedEventLines[key] = unmatched.isEmpty ? nil : unmatched
    }

    /// Resolve the default calendar identifier: user setting → TextCal fallback
    private func resolveDefaultCalendarId() async -> String? {
        if let settingsId = calendarSettings?.defaultCalendarIdentifier,
           let ekManager = eventKitManager,
           await ekManager.calendarForIdentifier(settingsId) != nil {
            return settingsId
        }
        // Fall back to TextCal calendar
        if let ekManager = eventKitManager,
           let textCal = await ekManager.getOrCreateCalendar() {
            return textCal.calendarIdentifier
        }
        return nil
    }

    // MARK: - Writing

    /// Update from the text editor. Saves full interleaved text, parses events for EventKit sync.
    /// Single-pass parsing: extracts journal lines and event groups simultaneously.
    func update(date: Date, text: String) {
        let key = DateFormatting.normalizeToDay(date)
        let lines = text.components(separatedBy: "\n")

        // Save the full interleaved text as-is (preserving user's layout order)
        let trimmed = text.trimmingCharacters(in: .newlines)
        if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dayTexts.removeValue(forKey: key)
            journals.removeValue(forKey: key)
            scheduleDayTextSave(date: key, text: "")
            return
        }

        dayTexts[key] = trimmed

        // Single pass: extract journal lines + event groups together
        var journalLines: [String] = []
        var parsedEvents: [ParsedEventGroup] = []
        var currentEvent: ParsedEventGroup?

        for line in lines {
            let parsed = LineParser.parse(line)
            switch parsed {
            case .event(let time, let endTime, let title, let recurrence, let calendarName):
                if let pending = currentEvent {
                    parsedEvents.append(pending)
                }
                currentEvent = ParsedEventGroup(
                    title: title,
                    startTime: time,
                    endTime: endTime,
                    isAllDay: false,
                    recurrence: recurrence,
                    notes: [],
                    calendarName: calendarName
                )

            case .allDay(let title, let recurrence, let calendarName):
                if let pending = currentEvent {
                    parsedEvents.append(pending)
                }
                currentEvent = ParsedEventGroup(
                    title: title,
                    startTime: nil,
                    endTime: nil,
                    isAllDay: true,
                    recurrence: recurrence,
                    notes: [],
                    calendarName: calendarName
                )

            case .eventNote(let noteText):
                if currentEvent != nil {
                    currentEvent?.notes.append(noteText)
                }

            case .journal, .blank:
                if let pending = currentEvent {
                    parsedEvents.append(pending)
                    currentEvent = nil
                }
                journalLines.append(line)
            }
        }

        if let pending = currentEvent {
            parsedEvents.append(pending)
        }

        // Update legacy journal text
        let journalText = journalLines.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        if journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            journals.removeValue(forKey: key)
        } else {
            journals[key] = journalText
        }

        // Save the full text to file (interleaved)
        syncStatus = .saving
        scheduleDayTextSave(date: key, text: trimmed)

        // Write events to EventKit (debounced to avoid syncing on every keystroke)
        if hasCalendarAccess && !parsedEvents.isEmpty {
            let events = parsedEvents
            syncTask?.cancel()
            syncTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else {
                    // Cancelled by a newer sync — let the newer task handle status
                    return
                }
                syncStatus = .syncing
                do {
                    try await syncEventsToEventKit(date: key, events: events)
                    await refreshEvents(for: key)
                    if !Task.isCancelled {
                        syncStatus = .idle
                    }
                } catch {
                    if !Task.isCancelled {
                        syncStatus = .error(Strings.syncFailed)
                    }
                }
            }
        } else {
            // No EventKit sync needed — go idle after file save is scheduled
            syncStatus = .idle
        }
    }

    /// Force an immediate save (e.g., on app background)
    func forceSave() async {
        guard let fileStore else { return }
        for (date, text) in dayTexts {
            do {
                try await fileStore.saveJournal(text, for: date)
            } catch {
                syncStatus = .error(Strings.saveFailed)
                return
            }
        }
    }

    // MARK: - EventKit Sync

    private func syncEventsToEventKit(date: Date, events: [ParsedEventGroup]) async throws {
        guard let ekManager = eventKitManager else { return }

        // Resolve the default calendar
        let defaultCal = await resolveDefaultCalendar()
        let defaultCalId = defaultCal?.calendarIdentifier

        // Separate events: ones going to the default calendar vs. override calendars
        var defaultCalEvents: [ParsedEventGroup] = []
        var overrideEvents: [(event: ParsedEventGroup, calendar: EKCalendar)] = []

        for event in events {
            if let name = event.calendarName,
               let cal = await ekManager.calendarByTitle(name),
               cal.calendarIdentifier != defaultCalId {
                // Explicit [CalendarName] override to a non-default calendar
                overrideEvents.append((event, cal))
            } else {
                // No prefix, or prefix matches the default → goes to default
                defaultCalEvents.append(event)
            }
        }

        // --- Default calendar: safe to delete-and-recreate (we own these events) ---
        if let defaultCal = defaultCal {
            let calId = defaultCal.calendarIdentifier
            let existingEvents = await ekManager.managedEvents(for: date, calendarIdentifier: calId)
            let existingRecurring = existingEvents.filter { $0.hasRecurrenceRules }

            // Remove only non-recurring events in the default calendar
            try await ekManager.removeManagedEvents(for: date, calendarIdentifier: calId)

            for event in defaultCalEvents {
                if matchesExistingRecurring(event, existing: existingRecurring, date: date) {
                    continue
                }
                try await saveEventToKit(event, date: date, calendar: defaultCal, ekManager: ekManager)
            }
        }

        // --- Override calendars: create-only (never delete events we don't own) ---
        for (event, cal) in overrideEvents {
            let existingInCal = await ekManager.managedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
            if matchesExistingEvent(event, existing: existingInCal, date: date) {
                continue  // already exists, don't duplicate
            }
            try await saveEventToKit(event, date: date, calendar: cal, ekManager: ekManager)
        }
    }

    /// Save a single parsed event to EventKit
    private func saveEventToKit(_ event: ParsedEventGroup, date: Date, calendar: EKCalendar, ekManager: EventKitManager) async throws {
        let ekRule: EKRecurrenceRule?
        if let recurrence = event.recurrence {
            ekRule = EventKitSync.ekRecurrenceRule(from: recurrence)
        } else {
            ekRule = nil
        }
        let notes = event.notes.isEmpty ? nil : event.notes.joined(separator: "\n")
        try await ekManager.saveEvent(
            title: event.title,
            date: date,
            startTime: event.startTime,
            endTime: event.endTime,
            isAllDay: event.isAllDay,
            notes: notes,
            recurrenceRule: ekRule,
            calendar: calendar
        )
    }

    /// Check if a parsed event matches ANY existing event (recurring or not) by title + time
    private func matchesExistingEvent(_ parsed: ParsedEventGroup, existing: [EKEvent], date: Date) -> Bool {
        let cal = Calendar.current
        for ekEvent in existing {
            guard ekEvent.title == parsed.title else { continue }
            guard ekEvent.isAllDay == parsed.isAllDay else { continue }
            if parsed.isAllDay { return true }
            if let startTime = parsed.startTime {
                let ekComps = cal.dateComponents([.hour, .minute], from: ekEvent.startDate)
                guard ekComps.hour == startTime.hour && ekComps.minute == startTime.minute else { continue }

                // Also compare end time so edits to duration are detected
                if let endTime = parsed.endTime {
                    let ekEndComps = cal.dateComponents([.hour, .minute], from: ekEvent.endDate)
                    guard ekEndComps.hour == endTime.hour && ekEndComps.minute == endTime.minute else { continue }
                }
                return true
            }
        }
        return false
    }

    /// Resolve the user's default calendar (setting → TextCal fallback)
    private func resolveDefaultCalendar() async -> EKCalendar? {
        guard let ekManager = eventKitManager else { return nil }
        if let settingsId = calendarSettings?.defaultCalendarIdentifier,
           let cal = await ekManager.calendarForIdentifier(settingsId) {
            return cal
        }
        return await ekManager.getOrCreateCalendar()
    }

    /// Check if a parsed event matches an existing recurring event occurrence
    private func matchesExistingRecurring(_ parsed: ParsedEventGroup, existing: [EKEvent], date: Date) -> Bool {
        let cal = Calendar.current
        for ekEvent in existing {
            guard ekEvent.title == parsed.title else { continue }
            guard ekEvent.isAllDay == parsed.isAllDay else { continue }

            if parsed.isAllDay {
                return true
            }

            // Compare start times and end times
            if let startTime = parsed.startTime {
                let ekComps = cal.dateComponents([.hour, .minute], from: ekEvent.startDate)
                guard ekComps.hour == startTime.hour && ekComps.minute == startTime.minute else { continue }

                // Also compare end time to distinguish events at the same start time
                if let endTime = parsed.endTime {
                    let ekEndComps = cal.dateComponents([.hour, .minute], from: ekEvent.endDate)
                    guard ekEndComps.hour == endTime.hour && ekEndComps.minute == endTime.minute else { continue }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Search

    /// Search result for a single day
    struct SearchResult {
        let date: Date
        let matchingLines: [String]
    }

    /// Search all day texts for lines containing the query (case-insensitive).
    /// Returns up to `maxResults` results sorted by date descending (most recent first).
    func searchDayTexts(query: String, maxResults: Int = 50) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lowered = query.lowercased()
        var results: [SearchResult] = []

        for (date, text) in dayTexts {
            let lines = text.components(separatedBy: "\n")
            let matching = lines.filter { $0.lowercased().contains(lowered) }
            if !matching.isEmpty {
                results.append(SearchResult(date: date, matchingLines: matching))
            }
        }

        results.sort { $0.date > $1.date }
        if results.count > maxResults {
            results = Array(results.prefix(maxResults))
        }
        return results
    }

    // MARK: - Persistence

    private func scheduleDayTextSave(date: Date, text: String) {
        guard let coalescer, let fileStore else { return }
        Task {
            await coalescer.enqueue(for: date) {
                try await fileStore.saveJournal(text, for: date)
            }
        }
    }

    // MARK: - Migration

    private func migrateLegacyIfNeeded() async {
        guard let fileStore else { return }
        let hasLegacy = await fileStore.hasLegacyFile()
        guard hasLegacy else { return }

        do {
            let content = try await fileStore.loadLegacy()
            let (entries, _, _) = DocumentSerializer.deserialize(content)

            for entry in entries where !entry.isEmpty {
                let text = entry.rawText.trimmingCharacters(in: .newlines)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dayTexts[entry.id] = text
                    journals[entry.id] = text
                    try await fileStore.saveJournal(text, for: entry.id)
                }
            }

            try await fileStore.removeLegacyFile()
        } catch {
            // Migration failed — leave legacy file in place
        }
    }
}

/// Key for matching event lines to EventKit calendar colors
struct EventColorKey: Hashable {
    let title: String
    let hour: Int?
    let minute: Int?
    let isAllDay: Bool
}

/// A group of parsed event data ready to write to EventKit
private struct ParsedEventGroup {
    let title: String
    let startTime: DateComponents?
    let endTime: DateComponents?
    let isAllDay: Bool
    let recurrence: RecurrenceRule?
    var notes: [String]
    let calendarName: String?
}
