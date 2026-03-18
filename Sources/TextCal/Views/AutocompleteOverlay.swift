import EventKit
import SwiftUI

/// Suggestion types for inline autocomplete
enum AutocompleteSuggestion: Identifiable, Equatable {
    case calendarName(String)
    case recurrence(pattern: String, display: String)
    case time(text: String)

    var id: String {
        switch self {
        case .calendarName(let name): return "cal:\(name)"
        case .recurrence(let pattern, _): return "rec:\(pattern)"
        case .time(let text): return "time:\(text)"
        }
    }

    var displayText: String {
        switch self {
        case .calendarName(let name): return "[\(name)]"
        case .recurrence(_, let display): return display
        case .time(let text): return text
        }
    }

    var insertText: String {
        switch self {
        case .calendarName(let name): return "\(name)]"
        case .recurrence(let pattern, _): return "\(pattern))"
        case .time(let text): return text
        }
    }
}

/// Detects autocomplete triggers in text and provides suggestions.
struct AutocompleteEngine {
    let calendarNames: [String]

    private static let recurrenceSuggestions: [(pattern: String, display: String)] = [
        ("daily", "(daily)"),
        ("every weekday", "(every weekday)"),
        ("every Monday", "(every Monday)"),
        ("every Tuesday", "(every Tuesday)"),
        ("every Wednesday", "(every Wednesday)"),
        ("every Thursday", "(every Thursday)"),
        ("every Friday", "(every Friday)"),
        ("every Saturday", "(every Saturday)"),
        ("every Sunday", "(every Sunday)"),
        ("every 2 weeks", "(every 2 weeks)"),
        ("weekly", "(weekly)"),
        ("monthly 1st", "(monthly 1st)"),
        ("monthly 15th", "(monthly 15th)"),
        ("yearly", "(yearly)"),
    ]

    private static let timeSuggestions: [String] = {
        var times: [String] = []
        for hour in 6...22 {
            for minute in stride(from: 0, to: 60, by: 15) {
                let h12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
                let ampm = hour >= 12 ? "PM" : "AM"
                let minStr = minute == 0 ? ":00" : ":\(String(format: "%02d", minute))"
                times.append("\(h12)\(minStr) \(ampm) - ")
            }
        }
        return times
    }()

    /// Analyze the current line being edited and return suggestions.
    /// `currentLine` is the text of the line the cursor is on.
    func suggestions(for currentLine: String) -> [AutocompleteSuggestion] {
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

        // Trigger: user typed "[" — suggest calendar names
        if let bracketIndex = currentLine.lastIndex(of: "[") {
            let afterBracket = String(currentLine[currentLine.index(after: bracketIndex)...])
            // Only suggest if there's no closing bracket yet
            if !afterBracket.contains("]") {
                let query = afterBracket.lowercased()
                let matches = calendarNames.filter { name in
                    query.isEmpty || name.lowercased().contains(query)
                }
                return matches.prefix(5).map { .calendarName($0) }
            }
        }

        // Trigger: user typed "(" — suggest recurrence patterns
        if let parenIndex = currentLine.lastIndex(of: "(") {
            let afterParen = String(currentLine[currentLine.index(after: parenIndex)...])
            if !afterParen.contains(")") {
                let query = afterParen.lowercased()
                let matches = Self.recurrenceSuggestions.filter { suggestion in
                    query.isEmpty || suggestion.pattern.lowercased().contains(query)
                }
                return matches.prefix(5).map { .recurrence(pattern: $0.pattern, display: $0.display) }
            }
        }

        // Trigger: line starts with a digit — suggest times
        if let first = trimmed.first, first.isNumber, !trimmed.contains("-") {
            let query = trimmed.lowercased()
            let matches = Self.timeSuggestions.filter { time in
                time.lowercased().hasPrefix(query)
            }
            return Array(matches.prefix(4)).map { .time(text: $0) }
        }

        return []
    }
}

/// Displays autocomplete suggestions as a horizontal row of chips above the keyboard.
struct AutocompleteSuggestionsView: View {
    let suggestions: [AutocompleteSuggestion]
    let onSelect: (AutocompleteSuggestion) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelect(suggestion)
                        } label: {
                            Text(suggestion.displayText)
                                .font(.system(.callout, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Insert \(suggestion.displayText)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }
}
