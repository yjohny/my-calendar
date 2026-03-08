import SwiftUI

/// Displays day text with subtle styling: event lines get a color accent on the time portion
struct StyledTextView: View {
    let text: String
    var eventLineInfos: [EventLineInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show EventKit events first
            ForEach(Array(eventLineInfos.enumerated()), id: \.offset) { _, info in
                styledLine(info.text, isFromEventKit: true, calendarColor: info.calendarColor)
            }
            // Then show journal text
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                styledLine(line, isFromEventKit: false, calendarColor: nil)
            }
        }
    }

    @ViewBuilder
    private func styledLine(_ line: String, isFromEventKit: Bool, calendarColor: Color?) -> some View {
        // Strip [CalendarName] prefix for display (we show color instead)
        let (displayLine, calName) = stripCalendarPrefix(line)

        if displayLine.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let match = LineParser.parseAllDayLine(displayLine) {
            allDayView(match: match, isFromEventKit: isFromEventKit, calendarColor: calendarColor, calendarName: calName)
        } else if let match = LineParser.parseEventLine(displayLine) {
            eventView(match: match, isFromEventKit: isFromEventKit, calendarColor: calendarColor, calendarName: calName)
        } else if displayLine.hasPrefix("  ") {
            Text(displayLine)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(displayLine)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Strip `[CalendarName]` prefix from a line for display purposes
    private func stripCalendarPrefix(_ line: String) -> (line: String, calendarName: String?) {
        if let result = LineParser.extractCalendarPrefix(line) {
            return (result.remainder, result.calendarName)
        }
        return (line, nil)
    }

    @ViewBuilder
    private func allDayView(match: AllDayMatch, isFromEventKit: Bool, calendarColor: Color? = nil, calendarName: String? = nil) -> some View {
        let starColor = calendarColor ?? Color.orange
        let result: Text = {
            var t = Text("★ ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(starColor)
            + Text(match.title)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            if let recurrence = match.recurrence {
                t = t + Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if let calName = calendarName {
                t = t + Text("  \(calName)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            return t
        }()
        result
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func eventView(match: EventLineMatch, isFromEventKit: Bool, calendarColor: Color? = nil, calendarName: String? = nil) -> some View {
        let timeColor = calendarColor ?? Color.accentColor
        let result: Text = {
            var t = Text(match.timeText)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(timeColor)

            if let endTime = match.endTimeText {
                t = t + Text("–")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(timeColor.opacity(0.7))
                + Text(endTime)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(timeColor.opacity(0.7))
            }

            t = t + Text(match.separator + match.title)
                .font(.system(.body, design: .monospaced))

            if let recurrence = match.recurrence {
                t = t + Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if let calName = calendarName {
                t = t + Text("  \(calName)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            return t
        }()
        result
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
