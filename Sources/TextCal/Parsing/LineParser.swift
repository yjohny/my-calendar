import Foundation

struct EventLineMatch {
    let timeText: String
    let separator: String
    let title: String
    let timeComponents: DateComponents
}

enum LineParser {
    /// Parse a single line into an EntryLine
    static func parse(_ line: String) -> EntryLine {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return .blank
        }

        if let match = parseEventLine(line) {
            return .event(time: match.timeComponents, title: match.title)
        }

        // Indented line (2+ spaces) — treat as event note if it follows an event
        if line.hasPrefix("  ") {
            return .eventNote(text: String(line.dropFirst(2)))
        }

        return .journal(text: line)
    }

    /// Try to parse a line as an event line. Returns match details or nil.
    static func parseEventLine(_ line: String) -> EventLineMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Try regex match
        guard let match = trimmed.wholeMatch(of: TimePatterns.eventLinePattern) else {
            return nil
        }

        let timeStr = String(match.1)
        let ampm = match.2.map(String.init)
        let separator = " \(match.3) "
        let title = String(match.4)

        guard let components = TimePatterns.parseTime(timeStr, ampm: ampm) else {
            return nil
        }

        let timeText = ampm != nil ? "\(timeStr) \(ampm!)" : timeStr

        return EventLineMatch(
            timeText: timeText,
            separator: separator,
            title: title,
            timeComponents: components
        )
    }

    /// Parse all lines in a day's text
    static func parseAll(_ text: String) -> [EntryLine] {
        text.components(separatedBy: "\n").map { parse($0) }
    }
}
