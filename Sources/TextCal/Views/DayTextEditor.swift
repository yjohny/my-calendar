import SwiftUI

struct DayTextEditor: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var isEditing = false
    @State private var eventLines: [String] = []
    @FocusState private var editorFocused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !eventLines.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollDisabled(true)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 12)
                    .focused($editorFocused)
                    .onChange(of: text) { _, newValue in
                        store.update(date: date, text: newValue)
                    }
                    .onChange(of: editorFocused) { _, focused in
                        if !focused {
                            isEditing = false
                            refreshState()
                        }
                    }
                    .onAppear {
                        // When entering edit mode, show the full combined text
                        text = store.displayText(for: date)
                        editorFocused = true
                    }
            } else if !hasContent {
                Text("Add events or notes...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                    }
            } else {
                StyledTextView(
                    text: store.journalText(for: date),
                    eventLines: eventLines
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
            }
        }
        .onAppear {
            refreshState()
        }
    }

    private func refreshState() {
        text = store.journalText(for: date)
        eventLines = store.eventLinesForDate(date)
        Task {
            await store.refreshEvents(for: date)
            eventLines = store.eventLinesForDate(date)
        }
    }
}
