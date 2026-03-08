import Foundation

enum DocumentSerializer {
    /// Header prefix used in the markdown file
    private static let headerPrefix = "# "
    private static let metadataMarker = "---"
    private static let exceptionsHeader = "exceptions:"
    private static let endsHeader = "ends:"

    /// Serialize the days dictionary into a markdown string, including recurrence metadata
    static func serialize(
        days: [Date: DayEntry],
        exceptions: Set<String> = [],
        endOverrides: [String: Date] = [:]
    ) -> String {
        let sortedDays = days.values
            .sorted { $0.date < $1.date }
            .filter { !$0.isEmpty }

        if sortedDays.isEmpty && exceptions.isEmpty && endOverrides.isEmpty {
            return ""
        }

        var lines: [String] = []
        for (index, day) in sortedDays.enumerated() {
            if index > 0 { lines.append("") }
            lines.append("\(headerPrefix)\(DateFormatting.headerString(for: day.date))")
            lines.append("")
            lines.append(day.rawText)
        }

        // Serialize recurrence metadata if any exists
        if !exceptions.isEmpty || !endOverrides.isEmpty {
            lines.append("")
            lines.append(metadataMarker)

            if !exceptions.isEmpty {
                lines.append(exceptionsHeader)
                for exception in exceptions.sorted() {
                    lines.append("- \(exception)")
                }
            }

            if !endOverrides.isEmpty {
                lines.append(endsHeader)
                for (eventId, endDate) in endOverrides.sorted(by: { $0.key < $1.key }) {
                    lines.append("- \(eventId)|\(endDate.timeIntervalSince1970)")
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Deserialize a markdown string into day entries and recurrence metadata
    static func deserialize(_ content: String) -> (entries: [DayEntry], exceptions: Set<String>, endOverrides: [String: Date]) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [], [:])
        }

        var entries: [DayEntry] = []
        var currentDate: Date?
        var currentLines: [String] = []
        var exceptions = Set<String>()
        var endOverrides: [String: Date] = [:]
        var inMetadata = false
        var currentMetadataSection = ""

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == metadataMarker {
                // Save previous entry
                if let date = currentDate {
                    let text = trimmedJoin(currentLines)
                    entries.append(DayEntry(id: date, rawText: text))
                    currentDate = nil
                    currentLines = []
                }
                inMetadata = true
                continue
            }

            if inMetadata {
                if line == exceptionsHeader {
                    currentMetadataSection = "exceptions"
                } else if line == endsHeader {
                    currentMetadataSection = "ends"
                } else if line.hasPrefix("- ") {
                    let value = String(line.dropFirst(2))
                    if currentMetadataSection == "exceptions" {
                        exceptions.insert(value)
                    } else if currentMetadataSection == "ends" {
                        let parts = value.components(separatedBy: "|")
                        if parts.count >= 2, let interval = Double(parts.last!) {
                            let eventId = parts.dropLast().joined(separator: "|")
                            endOverrides[eventId] = Date(timeIntervalSince1970: interval)
                        }
                    }
                }
                continue
            }

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

        return (entries, exceptions, endOverrides)
    }

    /// Join lines, trimming leading/trailing blank lines but preserving internal ones
    private static func trimmedJoin(_ lines: [String]) -> String {
        let joined = lines.joined(separator: "\n")
        return joined.trimmingCharacters(in: .newlines)
    }
}
