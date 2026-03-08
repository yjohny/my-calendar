import SwiftUI

struct DayTextEditor: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

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
                        }
                    }
                    .onAppear {
                        editorFocused = true
                    }
            } else if text.isEmpty {
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
                StyledTextView(text: text)
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
            text = store.text(for: date)
        }
    }
}
