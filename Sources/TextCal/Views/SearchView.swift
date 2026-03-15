import SwiftUI

struct SearchView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CalendarStore.SearchResult] = []
    let onSelect: (Date) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(Strings.searchPlaceholder, text: $query)
                        .font(.system(.body, design: .rounded))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        Strings.searchTitle,
                        systemImage: "magnifyingglass",
                        description: Text(Strings.searchDescription)
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(results, id: \.date) { result in
                            Section {
                                ForEach(Array(result.matchingLines.enumerated()), id: \.offset) { _, line in
                                    highlightedLine(line)
                                }
                            } header: {
                                Button {
                                    onSelect(result.date)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(DateFormatting.headerString(for: result.date))
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .onTapGesture {
                                onSelect(result.date)
                                dismiss()
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(Strings.searchNavTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text(Strings.done) }
                        .font(.system(.body, design: .rounded))
                }
            }
        }
        .task(id: query) {
            // Debounce search by 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = store.searchDayTexts(query: query)
        }
    }

    /// Render a line with the query text highlighted in bold
    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        let parsed = LineParser.parse(line)
        let isEvent: Bool = {
            switch parsed {
            case .event, .allDay: return true
            default: return false
            }
        }()

        let highlighted = buildHighlightedText(line, query: query, isEvent: isEvent)
        highlighted
            .font(.system(.body, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Build a Text view with matching portions highlighted
    private func buildHighlightedText(_ line: String, query: String, isEvent: Bool) -> Text {
        guard !query.isEmpty else {
            return Text(line)
        }

        let loweredLine = line.lowercased()
        let loweredQuery = query.lowercased()
        var result = Text("")
        var searchStart = loweredLine.startIndex

        while let range = loweredLine.range(of: loweredQuery, range: searchStart..<loweredLine.endIndex) {
            // Add non-matching prefix
            if searchStart < range.lowerBound {
                let prefix = String(line[searchStart..<range.lowerBound])
                result = result + Text(prefix)
                    .foregroundStyle(isEvent ? Color.primary : Color.primary)
            }
            // Add highlighted match
            let match = String(line[range])
            result = result + Text(match)
                .fontWeight(.bold)
                .foregroundStyle(isEvent ? Color.accentColor : Color.primary)
                .underline()
            searchStart = range.upperBound
        }

        // Add remaining text
        if searchStart < line.endIndex {
            let suffix = String(line[searchStart..<line.endIndex])
            result = result + Text(suffix)
        }

        return result
    }
}
