import Foundation

enum DateFormatting {
    /// Format used for date headers: "Monday, March 9, 2026"
    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    /// Format a date as a header string
    static func headerString(for date: Date) -> String {
        headerFormatter.string(from: date)
    }

    /// Parse a header string back into a date
    static func date(fromHeader header: String) -> Date? {
        headerFormatter.date(from: header)
    }

    /// Normalize a date to midnight in the current calendar
    static func normalizeToDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// Generate an array of dates from start to end (inclusive)
    static func dateRange(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var current = normalizeToDay(start)
        let normalizedEnd = normalizeToDay(end)

        while current <= normalizedEnd {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    /// Get today's date normalized to midnight
    static var today: Date {
        normalizeToDay(Date())
    }
}
