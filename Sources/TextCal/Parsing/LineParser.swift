import Foundation

struct EventLineMatch {
    let timeText: String
    let endTimeText: String?
    let separator: String
    let title: String
    let timeComponents: DateComponents
    let endTimeComponents: DateComponents?
    let recurrence: RecurrenceRule?
}

struct AllDayMatch {
    let title: String
    let recurrence: RecurrenceRule?
}

enum LineParser {
    /// Parse a single line into an EntryLine
    static func parse(_ line: String) -> EntryLine {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return .blank
        }

        // Check all-day event first (* prefix)
        if let match = parseAllDayLine(line) {
            return .allDay(title: match.title, recurrence: match.recurrence)
        }

        if let match = parseEventLine(line) {
            return .event(
                time: match.timeComponents,
                endTime: match.endTimeComponents,
                title: match.title,
                recurrence: match.recurrence
            )
        }

        // Indented line (2+ spaces) — treat as event note if it follows an event
        if line.hasPrefix("  ") {
            return .eventNote(text: String(line.dropFirst(2)))
        }

        return .journal(text: line)
    }

    /// Try to parse a line as an all-day event. Returns match or nil.
    static func parseAllDayLine(_ line: String) -> AllDayMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: TimePatterns.allDayPattern) else {
            return nil
        }

        var title = String(match.1)
        let recurrence = extractRecurrence(from: &title)
        return AllDayMatch(title: title, recurrence: recurrence)
    }

    /// Try to parse a line as an event line. Returns match details or nil.
    static func parseEventLine(_ line: String) -> EventLineMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Try time range pattern first: "9:00-10:30 AM - Meeting"
        if let rangeMatch = trimmed.wholeMatch(of: TimePatterns.timeRangeEventPattern) {
            let startTimeStr = String(rangeMatch.1)
            let startAmpm = rangeMatch.2.map(String.init)
            let endTimeStr = String(rangeMatch.3)
            let endAmpm = String(rangeMatch.4)
            let separator = " \(rangeMatch.5) "
            var title = String(rangeMatch.6)

            // For ranges like "9:00-10:30 AM", the AM/PM applies to both if start has none
            let effectiveStartAmpm = startAmpm ?? endAmpm

            guard let startComponents = TimePatterns.parseTime(startTimeStr, ampm: effectiveStartAmpm),
                  let endComponents = TimePatterns.parseTime(endTimeStr, ampm: endAmpm) else {
                return nil
            }

            let recurrence = extractRecurrence(from: &title)

            let startText = startAmpm != nil ? "\(startTimeStr) \(startAmpm!)" : startTimeStr
            let endText = "\(endTimeStr) \(endAmpm)"

            return EventLineMatch(
                timeText: startText,
                endTimeText: endText,
                separator: separator,
                title: title,
                timeComponents: startComponents,
                endTimeComponents: endComponents,
                recurrence: recurrence
            )
        }

        // Try simple event pattern
        guard let match = trimmed.wholeMatch(of: TimePatterns.eventLinePattern) else {
            return nil
        }

        let timeStr = String(match.1)
        let ampm = match.2.map(String.init)
        let separator = " \(match.3) "
        var title = String(match.4)

        guard let components = TimePatterns.parseTime(timeStr, ampm: ampm) else {
            return nil
        }

        let recurrence = extractRecurrence(from: &title)
        let timeText = ampm != nil ? "\(timeStr) \(ampm!)" : timeStr

        return EventLineMatch(
            timeText: timeText,
            endTimeText: nil,
            separator: separator,
            title: title,
            timeComponents: components,
            endTimeComponents: nil,
            recurrence: recurrence
        )
    }

    /// Extract recurrence pattern from end of title, modifying the title in place
    private static func extractRecurrence(from title: inout String) -> RecurrenceRule? {
        guard let match = title.firstMatch(of: TimePatterns.recurrencePattern) else {
            return nil
        }
        let recurrenceText = String(match.1)
        if let rule = TimePatterns.parseRecurrence(recurrenceText) {
            // Remove the recurrence marker from the title
            title = title.replacingOccurrences(of: String(match.0), with: "")
                .trimmingCharacters(in: .whitespaces)
            return rule
        }
        return nil
    }

    /// Parse all lines in a day's text
    static func parseAll(_ text: String) -> [EntryLine] {
        text.components(separatedBy: "\n").map { parse($0) }
    }
}
