import Foundation

/// Represents a recurrence pattern parsed from text like "(every weekday)" or "(daily)"
struct RecurrenceRule: Equatable, Codable {
    enum Frequency: Equatable, Codable {
        case daily
        case weekdays
        case weekly(weekday: Int)      // 1=Sunday, 2=Monday, ... 7=Saturday
        case biweekly(weekday: Int)
        case monthly(day: Int)         // day of month (1-31)
        case yearly(month: Int, day: Int)  // month (1-12) and day of month
    }

    let frequency: Frequency
    /// The raw text of the recurrence marker, e.g. "(every weekday)"
    let rawText: String

    /// Check if this rule applies to a given date
    func appliesTo(date: Date, sourceDate: Date) -> Bool {
        let calendar = Calendar.current

        // Never applies before the source date
        if calendar.compare(date, to: sourceDate, toGranularity: .day) == .orderedAscending {
            return false
        }

        // Source date itself always applies
        if calendar.isDate(date, inSameDayAs: sourceDate) {
            return true
        }

        switch frequency {
        case .daily:
            return true

        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6  // Mon-Fri

        case .weekly(let targetWeekday):
            let weekday = calendar.component(.weekday, from: date)
            return weekday == targetWeekday

        case .biweekly(let targetWeekday):
            let weekday = calendar.component(.weekday, from: date)
            guard weekday == targetWeekday else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: sourceDate, to: date).weekOfYear ?? 0
            return weeks % 2 == 0

        case .monthly(let targetDay):
            let day = calendar.component(.day, from: date)
            return day == targetDay

        case .yearly(let targetMonth, let targetDay):
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return month == targetMonth && day == targetDay
        }
    }
}
