import Foundation
import SwiftUI

@MainActor
@Observable
final class CalendarStore {
    /// Sparse map: only dates with non-empty content are stored
    private(set) var days: [Date: DayEntry] = [:]

    private var fileStore: FileStore?
    private var coalescer: ChangeCoalescer?

    init() {}

    /// Connect to persistence layer
    func configure(fileStore: FileStore, coalescer: ChangeCoalescer) {
        self.fileStore = fileStore
        self.coalescer = coalescer
    }

    /// Get the raw text for a date, or empty string if none
    func text(for date: Date) -> String {
        let key = DateFormatting.normalizeToDay(date)
        return days[key]?.rawText ?? ""
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

        scheduleSave()
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
            let loaded = DocumentSerializer.deserialize(content)
            for entry in loaded {
                if !entry.isEmpty {
                    days[entry.id] = entry
                }
            }
        } catch {
            // First launch or empty file — start fresh
        }
    }

    /// Force an immediate save (e.g., on app background)
    func forceSave() async {
        guard let fileStore else { return }
        let content = DocumentSerializer.serialize(days: days)
        try? await fileStore.save(content)
    }

    private func scheduleSave() {
        guard let coalescer, let fileStore else { return }
        let daysCopy = days
        Task {
            await coalescer.enqueue {
                let content = DocumentSerializer.serialize(days: daysCopy)
                try await fileStore.save(content)
            }
        }
    }
}
