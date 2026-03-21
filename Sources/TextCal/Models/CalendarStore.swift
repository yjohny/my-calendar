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
    private(set) var templateStore: TemplateStore = TemplateStore()

    /// Debounce EventKit sync to avoid re-syncing on every keystroke
    private var syncTask: Task<Void, Never>?

    /// LRU tracking for dayTexts cache eviction
    private var accessOrder: [Date] = []
    private var accessOrderSet: Set<Date> = []
    private let maxCachedDays = 180

    /// Cached parsed event keys to avoid re-parsing unchanged text
    private var parsedKeyCache: [Date: (hash: Int, keys: Set<EventColorKey>)] = [:]

    /// Tracks the last date that failed sync for retry
    private var lastFailedSyncDate: Date?

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
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                // Fresh start — no journal directory yet, this is expected
            } catch {
                syncStatus = .error("Failed to load data")
            }

            // Migrate from legacy single-file format if needed
            await migrateLegacyIfNeeded()
        }
    }

    // MARK: - LRU Cache

    /// Mark a date as recently accessed and evict old entries if needed
    private func touchDate(_ date: Date) {
        if accessOrderSet.contains(date) {
            accessOrder.removeAll { $0 == date }
        } else {
            accessOrderSet.insert(date)
        }
        accessOrder.append(date)
        evictIfNeeded()
    }

    /// Evict least-recently-accessed entries when cache exceeds threshold
    private func evictIfNeeded() {
        while accessOrder.count > maxCachedDays {
            let evicted = accessOrder.removeFirst()
            accessOrderSet.remove(evicted)
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
        let hidden = calendarSettings?.hiddenCalendarIdentifiers ?? []
        let ekEvents = await ekManager.events(for: key, excludingCalendars: hidden)
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

        let hidden = calendarSettings?.hiddenCalendarIdentifiers ?? []
        let allEvents = await ekManager.events(from: normalizedStart, to: rangeEnd, excludingCalendars: hidden)
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

    /// Pre-computed event info to avoid redundant dateComponents calls
    private struct ProcessedEKEvent {
        let event: EKEvent
        let colorKey: EventColorKey
        let color: Color
    }

    /// Shared logic: process EventKit events for a single date, building color map + unmatched list.
    /// Computes dateComponents once per event and reuses for both color map and unmatched detection.
    private func processEventsForDate(_ key: Date, ekEvents: [EKEvent], defaultCalId: String?) {
        let cal = Calendar.current

        // Pre-compute keys and colors once per event
        let processed: [ProcessedEKEvent] = ekEvents.map { event in
            let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let colorKey = EventColorKey(
                title: event.title ?? "",
                hour: event.isAllDay ? nil : comps.hour,
                minute: event.isAllDay ? nil : comps.minute,
                isAllDay: event.isAllDay
            )
            let color = EventKitSync.calendarColor(from: event)
            return ProcessedEKEvent(event: event, colorKey: colorKey, color: color)
        }

        // Build color map from pre-computed data
        var colorMap: [EventColorKey: Color] = [:]
        for item in processed {
            colorMap[item.colorKey] = item.color
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
                case .event(let time, _, let title, _, _, _):
                    keys.insert(EventColorKey(
                        title: title,
                        hour: time.hour,
                        minute: time.minute,
                        isAllDay: false
                    ))
                case .allDay(let title, _, _, _):
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

        // Reuse pre-computed keys for unmatched detection
        var unmatched: [EventLineInfo] = []
        for item in processed {
            if !userEventKeys.contains(item.colorKey) {
                let line = EventKitSync.textLine(from: item.event, defaultCalendarId: defaultCalId)
                unmatched.append(EventLineInfo(text: line, calendarColor: item.color))
            }
        }

        unmatchedEventLines[key] = unmatched.isEmpty ? nil : unmatched
    }

    /// Resolve the default calendar identifier: user setting → TextCal fallback
    private func resolveDefaultCalendarId() async -> String? {
        guard let ekManager = eventKitManager else { return nil }
        return await EventSyncCoordinator.resolveDefaultCalendarId(ekManager: ekManager, calendarSettings: calendarSettings)
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
            case .event(let time, let endTime, let title, let recurrence, let calendarName, let alarmOffset):
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
                    calendarName: calendarName,
                    alarmOffset: alarmOffset
                )

            case .allDay(let title, let recurrence, let calendarName, let alarmOffset):
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
                    calendarName: calendarName,
                    alarmOffset: alarmOffset
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
                        self.lastFailedSyncDate = key
                        syncStatus = .error(Strings.syncFailed)
                    }
                }
            }
        } else {
            // No EventKit sync needed — go idle after file save is scheduled
            syncStatus = .idle
        }
    }

    /// Move a line from one day's text to another day.
    /// Removes the line at `lineIndex` from `sourceDate` and appends it to `targetDate`.
    func moveEventLine(from sourceDate: Date, lineIndex: Int, to targetDate: Date) {
        let sourceKey = DateFormatting.normalizeToDay(sourceDate)
        let targetKey = DateFormatting.normalizeToDay(targetDate)

        guard let sourceText = dayTexts[sourceKey] else { return }
        var lines = sourceText.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return }

        let movedLine = lines.remove(at: lineIndex)
        let newSourceText = lines.joined(separator: "\n")
        update(date: sourceDate, text: newSourceText)

        let targetText = dayTexts[targetKey] ?? ""
        let newTargetText: String
        if targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newTargetText = movedLine
        } else {
            newTargetText = targetText + "\n" + movedLine
        }
        update(date: targetDate, text: newTargetText)
    }

    /// Retry the last failed sync operation
    func retryLastSync() async {
        guard let date = lastFailedSyncDate else { return }
        let key = DateFormatting.normalizeToDay(date)
        guard let text = dayTexts[key] else { return }
        update(date: date, text: text)
    }

    /// Force an immediate save of all pending changes (e.g., on app background or termination).
    /// Flushes the debounce coalescer to ensure queued saves execute immediately,
    /// cancels any in-flight EventKit sync task, and writes all cached day texts to disk.
    func forceSave() async {
        // Cancel any debounced EventKit sync — it's not safe during shutdown
        syncTask?.cancel()
        syncTask = nil

        // Flush the coalescer so any debounced file saves execute immediately
        if let coalescer {
            await coalescer.flush()
        }

        // Belt-and-suspenders: write all in-memory day texts to disk
        guard let fileStore else { return }
        var saveError: Error?
        for (date, text) in dayTexts {
            do {
                try await fileStore.saveJournal(text, for: date)
            } catch {
                saveError = error
            }
        }
        if saveError != nil {
            syncStatus = .error(Strings.saveFailed)
        }
    }

    // MARK: - EventKit Sync

    private func syncEventsToEventKit(date: Date, events: [ParsedEventGroup]) async throws {
        guard let ekManager = eventKitManager else { return }
        try await EventSyncCoordinator.syncEvents(
            date: date,
            events: events,
            ekManager: ekManager,
            calendarSettings: calendarSettings
        )
    }

    /// Resolve the user's default calendar (setting → TextCal fallback)
    private func resolveDefaultCalendar() async -> EKCalendar? {
        guard let ekManager = eventKitManager else { return nil }
        return await EventSyncCoordinator.resolveDefaultCalendar(ekManager: ekManager, calendarSettings: calendarSettings)
    }

    // MARK: - Search

    /// Search result for a single day
    struct SearchResult {
        let date: Date
        let matchingLines: [String]
    }

    /// Search all day texts for lines containing the query (case-insensitive).
    /// Delegates to CalendarSearchService. Searches most-recent dates first.
    func searchDayTexts(query: String, maxResults: Int = 50) -> [SearchResult] {
        CalendarSearchService.searchDayTexts(query: query, dayTexts: dayTexts, maxResults: maxResults)
    }

    /// Search result from EventKit (events not in user's text)
    struct EventKitSearchResult {
        let date: Date
        let matchingLines: [String]
    }

    /// Search EventKit events across ±1 year for titles matching the query.
    /// Delegates to CalendarSearchService. Uses parsed event keys for deduplication.
    func searchEventKitEvents(query: String, maxResults: Int = 50) async -> [EventKitSearchResult] {
        guard let ekManager = eventKitManager, hasCalendarAccess else { return [] }
        let defaultCalId = await resolveDefaultCalendarId()
        return await CalendarSearchService.searchEventKitEvents(
            query: query,
            dayTexts: dayTexts,
            ekManager: ekManager,
            defaultCalId: defaultCalId,
            maxResults: maxResults
        )
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

/// Represents a time conflict between two events on the same day
struct TimeConflict: Equatable {
    let title1: String
    let title2: String
    let hour: Int
    let minute: Int
}

/// Detects overlapping timed events in a day's text.
/// Returns the set of event titles that have conflicts.
func detectConflicts(in text: String) -> Set<String> {
    let lines = text.components(separatedBy: "\n")
    var events: [(title: String, startMinutes: Int, endMinutes: Int)] = []

    for line in lines {
        let parsed = LineParser.parse(line)
        switch parsed {
        case .event(let time, let endTime, let title, _, _, _):
            guard let h = time.hour, let m = time.minute else { continue }
            let startMin = h * 60 + m
            let endMin: Int
            if let endH = endTime?.hour, let endM = endTime?.minute {
                endMin = endH * 60 + endM
            } else {
                endMin = startMin + 60 // default 1 hour
            }
            events.append((title, startMin, endMin))
        default:
            break
        }
    }

    var conflicting = Set<String>()
    for i in 0..<events.count {
        for j in (i + 1)..<events.count {
            let a = events[i]
            let b = events[j]
            // Overlap: a starts before b ends AND b starts before a ends
            if a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes {
                conflicting.insert(a.title)
                conflicting.insert(b.title)
            }
        }
    }
    return conflicting
}

/// Key for matching event lines to EventKit calendar colors
struct EventColorKey: Hashable {
    let title: String
    let hour: Int?
    let minute: Int?
    let isAllDay: Bool
}

/// A group of parsed event data ready to write to EventKit
struct ParsedEventGroup {
    let title: String
    let startTime: DateComponents?
    let endTime: DateComponents?
    let isAllDay: Bool
    let recurrence: RecurrenceRule?
    var notes: [String]
    let calendarName: String?
    let alarmOffset: TimeInterval?
}
