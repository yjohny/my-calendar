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
    /// Journal text per date (only freeform text, not events)
    private(set) var journals: [Date: String] = [:]

    /// Cached event lines per date (rendered from EventKit), with calendar colors
    private(set) var eventLineInfos: [Date: [EventLineInfo]] = [:]

    /// Plain event lines for backwards compatibility (display text, edit mode)
    private(set) var eventLines: [Date: [String]] = [:]

    /// Whether EventKit access has been granted
    private(set) var hasCalendarAccess = false

    private(set) var eventKitManager: EventKitManager?
    private var fileStore: FileStore?
    private var coalescer: ChangeCoalescer?
    private(set) var calendarSettings: CalendarSettings?

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

        // Load journal text from per-day files
        if let fileStore {
            do {
                let allJournals = try await fileStore.loadAllJournals()
                for (date, text) in allJournals {
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

    /// Get the combined display text for a date: event lines + journal text
    func displayText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        let events = eventLines[key] ?? []
        let journal = journals[key] ?? ""

        var parts: [String] = []
        if !events.isEmpty {
            parts.append(events.joined(separator: "\n"))
        }
        if !journal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(journal)
        }
        return parts.joined(separator: "\n")
    }

    /// Get just the journal text for a date
    func journalText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        return journals[key] ?? ""
    }

    /// Get the event lines for a date (from EventKit)
    func eventLinesForDate(_ date: Date) -> [String] {
        let key = DateFormatting.normalizeToDay(date)
        return eventLines[key] ?? []
    }

    /// Get event line infos (with calendar colors) for a date
    func eventLineInfosForDate(_ date: Date) -> [EventLineInfo] {
        let key = DateFormatting.normalizeToDay(date)
        return eventLineInfos[key] ?? []
    }

    /// Refresh event lines from EventKit for a specific date
    func refreshEvents(for date: Date) async {
        guard let ekManager = eventKitManager, hasCalendarAccess else { return }
        let key = DateFormatting.normalizeToDay(date)
        let ekEvents = await ekManager.events(for: key)
        let defaultCalId = await resolveDefaultCalendarId()

        var lines: [String] = []
        var infos: [EventLineInfo] = []
        for event in ekEvents {
            let line = EventKitSync.textLine(from: event, defaultCalendarId: defaultCalId)
            let color = EventKitSync.calendarColor(from: event)
            lines.append(line)
            infos.append(EventLineInfo(text: line, calendarColor: color))

            let noteLines = EventKitSync.noteLines(from: event)
            for note in noteLines {
                lines.append(note)
                infos.append(EventLineInfo(text: note, calendarColor: color))
            }
        }
        eventLines[key] = lines.isEmpty ? nil : lines
        eventLineInfos[key] = infos.isEmpty ? nil : infos
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

    /// Update from the text editor. Parses the full text, separates events from journal,
    /// writes events to EventKit and journal to file storage.
    func update(date: Date, text: String) {
        let key = DateFormatting.normalizeToDay(date)
        let lines = text.components(separatedBy: "\n")

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
                } else {
                    journalLines.append(line)
                }

            case .journal:
                if let pending = currentEvent {
                    parsedEvents.append(pending)
                    currentEvent = nil
                }
                journalLines.append(line)

            case .blank:
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

        // Update journal text
        let journalText = journalLines.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        if journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            journals.removeValue(forKey: key)
        } else {
            journals[key] = journalText
        }

        // Save journal to file
        scheduleJournalSave(date: key, text: journalText)

        // Write events to EventKit
        if hasCalendarAccess && !parsedEvents.isEmpty {
            let events = parsedEvents
            Task {
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
        } else {
            journals[key] = text
        }
        scheduleJournalSave(date: key, text: text)
    }

    /// Force an immediate save (e.g., on app background)
    func forceSave() async {
        guard let fileStore else { return }
        for (date, text) in journals {
            try? await fileStore.saveJournal(text, for: date)
        }
    }

    // MARK: - EventKit Sync

    private func syncEventsToEventKit(date: Date, events: [ParsedEventGroup]) async {
        guard let ekManager = eventKitManager else { return }

        // Resolve the default calendar
        let defaultCal = await resolveDefaultCalendar()

        // Group events by their target calendar identifier
        var eventsByCalendar: [String: [ParsedEventGroup]] = [:]
        for event in events {
            let cal = await resolveCalendar(for: event, defaultCalendar: defaultCal)
            let calId = cal?.calendarIdentifier ?? defaultCal?.calendarIdentifier ?? ""
            eventsByCalendar[calId, default: []].append(event)
        }

        // For each target calendar, remove old non-recurring events and recreate
        for (calId, calEvents) in eventsByCalendar {
            guard !calId.isEmpty else { continue }

            let existingEvents = await ekManager.managedEvents(for: date, calendarIdentifier: calId)
            let existingRecurring = existingEvents.filter { $0.hasRecurrenceRules }

            // Remove non-recurring events we manage in this calendar
            await ekManager.removeManagedEvents(for: date, calendarIdentifier: calId)

            let targetCal = await ekManager.calendarForIdentifier(calId)

            for event in calEvents {
                if matchesExistingRecurring(event, existing: existingRecurring, date: date) {
                    continue
                }

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
                    calendar: targetCal
                )
            }
        }
    }

    /// Resolve which EKCalendar to use for a parsed event
    private func resolveCalendar(for event: ParsedEventGroup, defaultCalendar: EKCalendar?) async -> EKCalendar? {
        guard let ekManager = eventKitManager else { return defaultCalendar }
        if let name = event.calendarName,
           let cal = await ekManager.calendarByTitle(name) {
            return cal
        }
        return defaultCalendar
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

    // MARK: - Persistence

    private func scheduleJournalSave(date: Date, text: String) {
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
                let lines = entry.rawText.components(separatedBy: "\n")
                var journalLines: [String] = []

                for line in lines {
                    let parsed = LineParser.parse(line)
                    switch parsed {
                    case .event, .allDay:
                        // Events will be re-entered by the user or could be bulk-imported
                        // For now, preserve them as journal text during migration
                        journalLines.append(line)
                    case .eventNote:
                        journalLines.append(line)
                    case .journal:
                        journalLines.append(line)
                    case .blank:
                        journalLines.append(line)
                    }
                }

                let journalText = journalLines.joined(separator: "\n")
                    .trimmingCharacters(in: .newlines)
                if !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    journals[entry.id] = journalText
                    try await fileStore.saveJournal(journalText, for: entry.id)
                }
            }

            try await fileStore.removeLegacyFile()
        } catch {
            // Migration failed — leave legacy file in place
        }
    }
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
