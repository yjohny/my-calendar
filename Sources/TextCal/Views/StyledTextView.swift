import SwiftUI

/// Displays day text with subtle styling: event lines get a color accent on the time portion
struct StyledTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                styledLine(line)
            }
        }
    }

    @ViewBuilder
    private func styledLine(_ line: String) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let match = LineParser.parseEventLine(line) {
            HStack(spacing: 0) {
                Text(match.timeText)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                Text(match.separator + match.title)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
}
