import Foundation

enum TimePatterns {
    /// Matches time patterns like "9:00 AM", "14:30", "2 PM", "10:30 am"
    /// Captures: (hours, optional minutes, optional am/pm)
    static let timePattern = /^\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)?\s*/

    /// Matches event separator after the time: " - ", " -- ", ": "
    static let separatorPattern = /\s*[-–:]\s*/

    /// Full event line: time + separator + title
    static let eventLinePattern = /^\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)?\s*([-–:])\s*(.+)$/

    /// Time range event: "9:00-10:30 AM - Meeting" or "9:00 AM-10:30 AM - Meeting"
    /// Group 1: start time, Group 2: optional start AM/PM, Group 3: end time,
    /// Group 4: optional end AM/PM, Group 5: separator, Group 6: title
    static let timeRangeEventPattern = /^\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)?\s*[-–]\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)\s*([-–:])\s*(.+)$/

    /// All-day event: "* Event title"
    static let allDayPattern = /^\s*\*\s+(.+)$/

    /// Recurrence pattern at end of title: "(every weekday)", "(daily)", etc.
    static let recurrencePattern = /\(([^)]+)\)\s*$/

    /// Parses a time string like "9:00 AM" or "14:30" into DateComponents
    static func parseTime(_ timeStr: String, ampm: String? = nil) -> DateComponents? {
        let parts = timeStr.split(separator: ":")
        guard let hourStr = parts.first, var hour = Int(hourStr) else { return nil }

        var minute = 0
        if parts.count > 1, let m = Int(parts[1]) {
            minute = m
        }

        if let ampm = ampm?.uppercased() {
            if ampm == "PM" && hour != 12 {
                hour += 12
            } else if ampm == "AM" && hour == 12 {
                hour = 0
            }
        }

        return DateComponents(hour: hour, minute: minute)
    }

    /// Parse a recurrence string like "every weekday", "daily", "every Tuesday"
    static func parseRecurrence(_ text: String) -> RecurrenceRule? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()

        if trimmed == "daily" {
            return RecurrenceRule(frequency: .daily, rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        if trimmed == "every weekday" || trimmed == "weekdays" {
            return RecurrenceRule(frequency: .weekdays, rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        // "every Monday", "every tuesday", etc.
        let weekdayNames = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ]
        for (name, value) in weekdayNames {
            if trimmed == "every \(name)" {
                return RecurrenceRule(frequency: .weekly(weekday: value), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
            }
        }

        if trimmed == "every week" || trimmed == "weekly" {
            // Default to the same weekday as the source date — resolved at materialization time
            // For parsing, we'll use 0 as a sentinel meaning "same weekday as source"
            return RecurrenceRule(frequency: .weekly(weekday: 0), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        if trimmed == "every 2 weeks" || trimmed == "biweekly" {
            return RecurrenceRule(frequency: .biweekly(weekday: 0), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        if trimmed == "monthly" {
            return RecurrenceRule(frequency: .monthly(day: 0), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        // "monthly 1st", "monthly 15th"
        if trimmed.hasPrefix("monthly ") {
            let dayStr = trimmed.dropFirst("monthly ".count)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "st", with: "")
                .replacingOccurrences(of: "nd", with: "")
                .replacingOccurrences(of: "rd", with: "")
                .replacingOccurrences(of: "th", with: "")
            if let day = Int(dayStr), day >= 1 && day <= 31 {
                return RecurrenceRule(frequency: .monthly(day: day), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
            }
        }

        if trimmed == "yearly" || trimmed == "every year" || trimmed == "annually" {
            // Sentinel 0,0 — resolved to source date's month/day at materialization time
            return RecurrenceRule(frequency: .yearly(month: 0, day: 0), rawText: "(\(text.trimmingCharacters(in: .whitespaces)))")
        }

        return nil
    }
}
