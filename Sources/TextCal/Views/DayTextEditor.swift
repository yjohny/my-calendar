import SwiftUI

struct DayTextEditor: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var isEditing = false
    @State private var colorMap: [EventColorKey: Color] = [:]
    @State private var unmatchedEvents: [EventLineInfo] = []
    @State private var refreshTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !unmatchedEvents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                TextEditor(text: $text)
                    .font(.system(.body, design: .rounded))
                    .scrollDisabled(true)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 12)
                    .focused($editorFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                editorFocused = false
                            }
                            .fontWeight(.medium)
                        }
                    }
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
                        // Show the full interleaved text for editing
                        text = store.displayText(for: date)
                        editorFocused = true
                    }
            } else if !hasContent {
                Text("Type events like 9:00 AM - Meeting, or just write...")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                    }
            } else {
                StyledTextView(
                    text: text,
                    colorMap: colorMap,
                    unmatchedEvents: unmatchedEvents
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
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
        // Load the full interleaved text from store
        text = store.dayTexts[DateFormatting.normalizeToDay(date)] ?? ""
        colorMap = store.colorMap(for: date)
        unmatchedEvents = store.unmatchedEvents(for: date)
        refreshTask?.cancel()
        let refreshDate = date
        refreshTask = Task {
            await store.refreshEvents(for: refreshDate)
            guard !Task.isCancelled else { return }
            colorMap = store.colorMap(for: refreshDate)
            unmatchedEvents = store.unmatchedEvents(for: refreshDate)
        }
    }
}
