import Foundation
import SwiftUI

@MainActor
@Observable
final class CalendarStore {
    /// Sparse map: only dates with non-empty content are stored
    private(set) var days: [Date: DayEntry] = [:]

    /// Manages recurring events and their materialization
    let recurrenceStore = RecurrenceStore()

    private var fileStore: FileStore?
    private var coalescer: ChangeCoalescer?

    init() {}

    /// Connect to persistence layer
    func configure(fileStore: FileStore, coalescer: ChangeCoalescer) {
        self.fileStore = fileStore
        self.coalescer = coalescer
    }

    /// Get the raw user-typed text for a date, or empty string if none
    func text(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        return days[key]?.rawText ?? ""
    }

    /// Get the effective text for a date: user text + materialized recurring events
    func effectiveText(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        let userText = days[key]?.rawText ?? ""
        let materializedLines = recurrenceStore.materializedLines(for: key)

        if materializedLines.isEmpty {
            return userText
        }

        let materialized = materializedLines.joined(separator: "\n")
        if userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return materialized
        }

        return materialized + "\n" + userText
    }

    /// Update the text for a date, triggering a debounced save
    func update(date: Date, text: String) {
        let key = DateFormatting.normalizeToDay(date)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            days.removeValue(forKey: key)
        } else {
            days[key] = DayEntry(id: key, rawText: text)
        }

        recurrenceStore.rebuildIndex(from: days)
        scheduleSave()
    }

    /// Remove a single materialized recurring event from a specific date
    func skipRecurringEvent(line: String, on date: Date) {
        if let event = recurrenceStore.findEvent(forLine: line, on: date) {
            recurrenceStore.addException(eventId: event.id, date: date)
            scheduleSave()
        }
    }

    /// End a recurring event from a specific date forward
    func endRecurringEvent(line: String, from date: Date) {
        if let event = recurrenceStore.findEvent(forLine: line, on: date) {
            recurrenceStore.endRecurrence(eventId: event.id, from: date)
            scheduleSave()
        }
    }

    /// Get DayEntry objects for a contiguous date range, filling in empty days
    func entries(from start: Date, to end: Date) -> [DayEntry] {
        DateFormatting.dateRange(from: start, to: end).map { date in
            days[date] ?? DayEntry(id: date, rawText: "")
        }
    }

    /// Load from disk
    func load() async {
        guard let fileStore else { return }
        do {
            let content = try await fileStore.load()
            let (loaded, exceptions, endOverrides) = DocumentSerializer.deserialize(content)
            for entry in loaded {
                if !entry.isEmpty {
                    days[entry.id] = entry
                }
            }
            recurrenceStore.rebuildIndex(from: days)

            // Restore exceptions and end overrides
            for exception in exceptions {
                recurrenceStore.exceptions.insert(exception)
            }
            for (eventId, endDate) in endOverrides {
                recurrenceStore.endOverrides[eventId] = endDate
            }
        } catch {
            // First launch or empty file — start fresh
        }
    }

    /// Force an immediate save (e.g., on app background)
    func forceSave() async {
        guard let fileStore else { return }
        let content = DocumentSerializer.serialize(
            days: days,
            exceptions: recurrenceStore.exceptions,
            endOverrides: recurrenceStore.endOverrides
        )
        try? await fileStore.save(content)
    }

    private func scheduleSave() {
        guard let coalescer, let fileStore else { return }
        let daysCopy = days
        let exceptions = recurrenceStore.exceptions
        let endOverrides = recurrenceStore.endOverrides
        Task {
            await coalescer.enqueue {
                let content = DocumentSerializer.serialize(
                    days: daysCopy,
                    exceptions: exceptions,
                    endOverrides: endOverrides
                )
                try await fileStore.save(content)
            }
        }
    }
}
