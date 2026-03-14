import EventKit
import Foundation
import SwiftUI

/// A rendered event line with its calendar color for display
struct EventLineInfo: Equatable {
    let text: String
    let calendarColor: Color

    static func == (lhs: EventLineInfo, rhs: EventLineInfo) -> Bool {
        lhs.text == rhs.text
    }
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

    private(set) var eventKitManager: EventKitManager?
    private var fileStore: FileStore?
    private var coalescer: ChangeCoalescer?
    private(set) var calendarSettings: CalendarSettings?

    /// Debounce EventKit sync to avoid re-syncing on every keystroke
    private var syncTask: Task<Void, Never>?

    // Keep legacy properties for compatibility during transition
    private(set) var eventLineInfos: [Date: [EventLineInfo]] = [:]
    private(set) var eventLines: [Date: [String]] = [:]
    /// Journal text per date (only freeform text, not events) — kept for migration
    private(set) var journals: [Date: String] = [:]

    init() {}

    /// Connect to persistence layers
    func configure(eventKitManager: EventKitManager, fileStore: FileStore, coalescer: ChangeCoalescer, calendarSettings: CalendarSettings = CalendarSettings()) {
        self.eventKitManager = eventKitManager
        self.fileStore = fileStore
        self.coalescer = coalescer
        self.calendarSettings = calendarSettings
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

    // MARK: - Reading

    /// Get the full display text for a date (interleaved events + journal in user order)
    func displayText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
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

    /// Get just the journal text for a date (legacy compatibility)
    func journalText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        return journals[key] ?? ""
    }

    /// Get the event lines for a date (from EventKit) — legacy compatibility
    func eventLinesForDate(_ date: Date) -> [String] {
        let key = DateFormatting.normalizeToDay(date)
        return eventLines[key] ?? []
    }

    /// Get event line infos (with calendar colors) for a date — legacy compatibility
    func eventLineInfosForDate(_ date: Date) -> [EventLineInfo] {
        let key = DateFormatting.normalizeToDay(date)
        return eventLineInfos[key] ?? []
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

        var colorMap: [EventColorKey: Color] = [:]
        var allInfos: [EventLineInfo] = []
        var allLines: [String] = []

        for event in ekEvents {
            let line = EventKitSync.textLine(from: event, defaultCalendarId: defaultCalId)
            let color = EventKitSync.calendarColor(from: event)
            allLines.append(line)
            allInfos.append(EventLineInfo(text: line, calendarColor: color))

            // Build color key from EventKit event
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let colorKey = EventColorKey(
                title: event.title ?? "",
                hour: comps.hour,
                minute: comps.minute,
                isAllDay: event.isAllDay
            )
            colorMap[colorKey] = color

            let noteLines = EventKitSync.noteLines(from: event)
            for note in noteLines {
                allLines.append(note)
                allInfos.append(EventLineInfo(text: note, calendarColor: color))
            }
        }

        eventColorMap[key] = colorMap
        eventLines[key] = allLines.isEmpty ? nil : allLines
        eventLineInfos[key] = allInfos.isEmpty ? nil : allInfos

        // Find EventKit events not represented in user's text
        let userText = dayTexts[key] ?? ""
        let userLines = userText.components(separatedBy: "\n")
        var userEventKeys = Set<EventColorKey>()

        for line in userLines {
            let parsed = LineParser.parse(line)
            switch parsed {
            case .event(let time, _, let title, _, _):
                userEventKeys.insert(EventColorKey(
                    title: title,
                    hour: time.hour,
                    minute: time.minute,
                    isAllDay: false
                ))
            case .allDay(let title, _, _):
                userEventKeys.insert(EventColorKey(
                    title: title,
                    hour: nil,
                    minute: nil,
                    isAllDay: true
                ))
            default:
                break
            }
        }

        var unmatched: [EventLineInfo] = []
        for event in ekEvents {
            let cal = Calendar.current
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
        scheduleDayTextSave(date: key, text: trimmed)

        // Write events to EventKit (debounced to avoid syncing on every keystroke)
        if hasCalendarAccess && !parsedEvents.isEmpty {
            let events = parsedEvents
            syncTask?.cancel()
            syncTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await syncEventsToEventKit(date: key, events: events)
                await refreshEvents(for: key)
            }
        }
    }

    /// Update just the journal text (no event parsing)
    func updateJournal(date: Date, text: String) {
        let key = DateFormatting.normalizeToDay(date)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            journals.removeValue(forKey: key)
            dayTexts.removeValue(forKey: key)
        } else {
            journals[key] = text
            dayTexts[key] = text
        }
        scheduleDayTextSave(date: key, text: text)
    }

    /// Force an immediate save (e.g., on app background)
    func forceSave() async {
        guard let fileStore else { return }
        for (date, text) in dayTexts {
            try? await fileStore.saveJournal(text, for: date)
        }
    }

    // MARK: - EventKit Sync

    private func syncEventsToEventKit(date: Date, events: [ParsedEventGroup]) async {
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
            await ekManager.removeManagedEvents(for: date, calendarIdentifier: calId)

            for event in defaultCalEvents {
                if matchesExistingRecurring(event, existing: existingRecurring, date: date) {
                    continue
                }
                await saveEventToKit(event, date: date, calendar: defaultCal, ekManager: ekManager)
            }
        }

        // --- Override calendars: create-only (never delete events we don't own) ---
        for (event, cal) in overrideEvents {
            let existingInCal = await ekManager.managedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
            if matchesExistingEvent(event, existing: existingInCal, date: date) {
                continue  // already exists, don't duplicate
            }
            await saveEventToKit(event, date: date, calendar: cal, ekManager: ekManager)
        }
    }

    /// Save a single parsed event to EventKit
    private func saveEventToKit(_ event: ParsedEventGroup, date: Date, calendar: EKCalendar, ekManager: EventKitManager) async {
        let ekRule: EKRecurrenceRule?
        if let recurrence = event.recurrence {
            ekRule = EventKitSync.ekRecurrenceRule(from: recurrence)
        } else {
            ekRule = nil
        }
        let notes = event.notes.isEmpty ? nil : event.notes.joined(separator: "\n")
        await ekManager.saveEvent(
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

            // Compare start times
            if let startTime = parsed.startTime {
                let ekComps = cal.dateComponents([.hour, .minute], from: ekEvent.startDate)
                if ekComps.hour == startTime.hour && ekComps.minute == startTime.minute {
                    return true
                }
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
    /// Returns results sorted by date descending (most recent first).
    func searchDayTexts(query: String) -> [SearchResult] {
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

        return results.sorted { $0.date > $1.date }
    }

    // MARK: - Persistence

    private func scheduleDayTextSave(date: Date, text: String) {
        guard let coalescer, let fileStore else { return }
        Task {
            await coalescer.enqueue {
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
