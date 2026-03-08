import SwiftUI

/// Displays day text with subtle styling: event lines get a color accent on the time portion
struct StyledTextView: View {
    let text: String
    var eventLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show EventKit events first
            ForEach(Array(eventLines.enumerated()), id: \.offset) { _, line in
                styledLine(line, isFromEventKit: true)
            }
            // Then show journal text
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                styledLine(line, isFromEventKit: false)
            }
        }
    }

    @ViewBuilder
    private func styledLine(_ line: String, isFromEventKit: Bool) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let match = LineParser.parseAllDayLine(line) {
            allDayView(match: match, isFromEventKit: isFromEventKit)
        } else if let match = LineParser.parseEventLine(line) {
            eventView(match: match, isFromEventKit: isFromEventKit)
        } else if line.hasPrefix("  ") {
            Text(line)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(line)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func allDayView(match: AllDayMatch, isFromEventKit: Bool) -> some View {
        let result: Text = {
            var t = Text("★ ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.orange)
            + Text(match.title)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            if let recurrence = match.recurrence {
                t = t + Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            return t
        }()
        result
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func eventView(match: EventLineMatch, isFromEventKit: Bool) -> some View {
        let result: Text = {
            var t = Text(match.timeText)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)

            if let endTime = match.endTimeText {
                t = t + Text("–")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                + Text(endTime)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }

            t = t + Text(match.separator + match.title)
                .font(.system(.body, design: .monospaced))

            if let recurrence = match.recurrence {
                t = t + Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            return t
        }()
        result
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
