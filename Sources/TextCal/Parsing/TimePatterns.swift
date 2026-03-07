import Foundation

enum TimePatterns {
    /// Matches time patterns like "9:00 AM", "14:30", "2 PM", "10:30 am"
    /// Captures: (hours, optional minutes, optional am/pm)
    static let timePattern = /^\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)?\s*/

    /// Matches event separator after the time: " - ", " -- ", ": "
    static let separatorPattern = /\s*[-–:]\s*/

    /// Full event line: time + separator + title
    static let eventLinePattern = /^\s*(\d{1,2}(?::\d{2})?)\s*(AM|PM|am|pm)?\s*([-–:])\s*(.+)$/

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
}
