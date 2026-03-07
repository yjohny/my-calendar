import Foundation

struct DayEntry: Identifiable, Equatable {
    /// The calendar date (normalized to midnight in the user's calendar)
    let id: Date
    /// The full user-typed text under this date header
    var rawText: String

    var isEmpty: Bool {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Convenience: the date for this entry
    var date: Date { id }
}
