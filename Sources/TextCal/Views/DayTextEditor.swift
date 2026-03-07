import SwiftUI

struct DayTextEditor: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var isFocused: Bool = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty && !editorFocused {
                Text("Add events or notes...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            // Styled text display (shows when not editing this day)
            if !editorFocused && !text.isEmpty {
                StyledTextView(text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editorFocused = true
                    }
            }

            // Editor (shown when focused)
            if editorFocused || (text.isEmpty && !editorFocused) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollDisabled(true)
                    .frame(minHeight: 36)
                    .padding(.horizontal, 12)
                    .focused($editorFocused)
                    .opacity(editorFocused ? 1 : (text.isEmpty ? 0.01 : 0))
                    .onChange(of: text) { _, newValue in
                        store.update(date: date, text: newValue)
                    }
            }
        }
        .onAppear {
            text = store.text(for: date)
        }
    }
}
