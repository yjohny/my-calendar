import Foundation

enum DocumentSerializer {
    /// Header prefix used in the markdown file
    private static let headerPrefix = "# "

    /// Serialize the days dictionary into a markdown string
    static func serialize(days: [Date: DayEntry]) -> String {
        let sortedDays = days.values
            .sorted { $0.date < $1.date }
            .filter { !$0.isEmpty }

        if sortedDays.isEmpty { return "" }

        var lines: [String] = []
        for (index, day) in sortedDays.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("\(headerPrefix)\(DateFormatting.headerString(for: day.date))")
            lines.append("")
            lines.append(day.rawText)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Deserialize a markdown string into an array of DayEntry
    static func deserialize(_ content: String) -> [DayEntry] {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var entries: [DayEntry] = []
        var currentDate: Date?
        var currentLines: [String] = []

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix(headerPrefix) {
                // Save previous entry if exists
                if let date = currentDate {
                    let text = trimmedJoin(currentLines)
                    entries.append(DayEntry(id: date, rawText: text))
                }

                // Parse new date header
                let headerText = String(line.dropFirst(headerPrefix.count))
                currentDate = DateFormatting.date(fromHeader: headerText)
                currentLines = []
            } else if currentDate != nil {
                currentLines.append(line)
            }
        }

        // Don't forget the last entry
        if let date = currentDate {
            let text = trimmedJoin(currentLines)
            entries.append(DayEntry(id: date, rawText: text))
        }

        return entries
    }

    /// Join lines, trimming leading/trailing blank lines but preserving internal ones
    private static func trimmedJoin(_ lines: [String]) -> String {
        let joined = lines.joined(separator: "\n")
        return joined.trimmingCharacters(in: .newlines)
    }
}
