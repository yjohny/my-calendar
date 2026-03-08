import SwiftUI

/// Displays day text with subtle styling: event lines get a color accent on the time portion
struct StyledTextView: View {
    let text: String
    var materializedLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Show materialized recurring events first
            ForEach(Array(materializedLines.enumerated()), id: \.offset) { _, line in
                styledLine(line, isMaterialized: true)
            }
            // Then show user-typed text
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                styledLine(line, isMaterialized: false)
            }
        }
    }

    @ViewBuilder
    private func styledLine(_ line: String, isMaterialized: Bool) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let match = LineParser.parseAllDayLine(line) {
            allDayView(match: match, isMaterialized: isMaterialized)
        } else if let match = LineParser.parseEventLine(line) {
            eventView(match: match, isMaterialized: isMaterialized)
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
    private func allDayView(match: AllDayMatch, isMaterialized: Bool) -> some View {
        HStack(spacing: 0) {
            Text("★ ")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Color.orange)
            Text(match.title)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            if let recurrence = match.recurrence {
                Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(isMaterialized ? 0.75 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func eventView(match: EventLineMatch, isMaterialized: Bool) -> some View {
        HStack(spacing: 0) {
            // Time display
            Text(match.timeText)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)

            // End time (time range)
            if let endTime = match.endTimeText {
                Text("–")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.accentColor.opacity(0.7))
                Text(endTime)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor.opacity(0.7))
            }

            Text(match.separator + match.title)
                .font(.system(.body, design: .monospaced))

            if let recurrence = match.recurrence {
                Text(" " + recurrence.rawText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(isMaterialized ? 0.75 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
