import SwiftUI

struct DayTextEditor: View {
    let date: Date
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var isEditing = false
    @State private var colorMap: [EventColorKey: Color] = [:]
    @State private var unmatchedEvents: [EventLineInfo] = []
    @State private var refreshTask: Task<Void, Never>?
    @State private var showingTemplates = false
    @State private var autocompleteSuggestions: [AutocompleteSuggestion] = []
    @State private var calendarNames: [String] = []
    /// Tracks whether the user has made edits this session (prevents refreshState from clobbering undo stack)
    @State private var hasEditedThisSession = false
    @FocusState private var editorFocused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !unmatchedEvents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                // Autocomplete suggestions bar
                AutocompleteSuggestionsView(suggestions: autocompleteSuggestions) { suggestion in
                    applySuggestion(suggestion)
                }

                TextEditor(text: $text)
                    .font(.system(.body, design: .rounded))
                    .scrollDisabled(true)
                    .frame(minHeight: 60)
                    .padding(.horizontal, 12)
                    .focused($editorFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Button {
                                showingTemplates = true
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .accessibilityLabel("Insert template")
                            Spacer()
                            Button {
                                editorFocused = false
                            } label: {
                                Text(Strings.done)
                            }
                            .fontWeight(.medium)
                        }
                    }
                    .onChange(of: text) { _, newValue in
                        hasEditedThisSession = true
                        store.update(date: date, text: newValue)
                        updateAutocompleteSuggestions()
                    }
                    .onChange(of: editorFocused) { _, focused in
                        if !focused {
                            isEditing = false
                            autocompleteSuggestions = []
                            refreshStatePreservingEdits()
                        }
                    }
                    .onAppear {
                        // Show the full interleaved text for editing
                        text = store.displayText(for: date)
                        hasEditedThisSession = false
                        editorFocused = true
                        loadCalendarNames()
                    }
                    .sheet(isPresented: $showingTemplates) {
                        TemplatePickerView(
                            templateStore: store.templateStore,
                            onInsert: { templateText in
                                insertTemplate(templateText)
                            }
                        )
                    }
            } else if !hasContent {
                Text(Strings.editorPlaceholder)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                    }
                    .accessibilityLabel("No events for \(DateFormatting.headerString(for: date))")
                    .accessibilityHint("Double tap to add events or notes")
            } else {
                StyledTextView(
                    text: text,
                    colorMap: colorMap,
                    unmatchedEvents: unmatchedEvents,
                    conflictingTitles: detectConflicts(in: text),
                    onMoveEvent: { lineIndex, targetDate in
                        store.moveEventLine(from: date, lineIndex: lineIndex, to: targetDate)
                        refreshState()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
                .accessibilityLabel("Events and notes for \(DateFormatting.headerString(for: date))")
                .accessibilityHint("Double tap to edit")
            }
        }
        .onAppear {
            refreshState()
        }
    }

    private func insertTemplate(_ templateText: String) {
        if text.isEmpty || text.hasSuffix("\n") {
            text += templateText
        } else {
            text += "\n" + templateText
        }
        store.update(date: date, text: text)
    }

    private func loadCalendarNames() {
        Task {
            if let ekManager = store.eventKitManager {
                let calendars = await ekManager.allCalendars()
                calendarNames = calendars.map(\.title)
            }
        }
    }

    private func updateAutocompleteSuggestions() {
        let lines = text.components(separatedBy: "\n")
        let currentLine = lines.last ?? ""
        let engine = AutocompleteEngine(calendarNames: calendarNames)
        autocompleteSuggestions = engine.suggestions(for: currentLine)
    }

    private func applySuggestion(_ suggestion: AutocompleteSuggestion) {
        let lines = text.components(separatedBy: "\n")
        guard var lastLine = lines.last else { return }

        switch suggestion {
        case .calendarName:
            if let bracketIndex = lastLine.lastIndex(of: "[") {
                lastLine = String(lastLine[...bracketIndex]) + suggestion.insertText
            }
        case .recurrence:
            if let parenIndex = lastLine.lastIndex(of: "(") {
                lastLine = String(lastLine[...parenIndex]) + suggestion.insertText
            }
        case .time:
            lastLine = suggestion.insertText
        }

        var updatedLines = Array(lines.dropLast())
        updatedLines.append(lastLine)
        text = updatedLines.joined(separator: "\n")
        store.update(date: date, text: text)
        autocompleteSuggestions = []
    }

    /// Refresh state after dismissing the editor — preserves the user's edited text
    /// instead of overwriting it, which would clear the undo stack.
    private func refreshStatePreservingEdits() {
        // Don't overwrite text — keep the user's current edits as the source of truth.
        // Only refresh the color map and unmatched events from EventKit.
        colorMap = store.colorMap(for: date)
        unmatchedEvents = store.unmatchedEvents(for: date)

        // Async refresh EventKit data for updated colors
        refreshTask?.cancel()
        let refreshDate = date
        refreshTask = Task {
            await store.refreshEvents(for: refreshDate)
            guard !Task.isCancelled else { return }
            colorMap = store.colorMap(for: refreshDate)
            unmatchedEvents = store.unmatchedEvents(for: refreshDate)
        }
        hasEditedThisSession = false
    }

    /// Full state refresh (used on initial appear, not after editing)
    private func refreshState() {
        let key = DateFormatting.normalizeToDay(date)
        text = store.dayTexts[key] ?? ""
        colorMap = store.colorMap(for: date)
        unmatchedEvents = store.unmatchedEvents(for: date)
        refreshTask?.cancel()
        let refreshDate = date
        refreshTask = Task {
            await store.ensureLoaded(for: refreshDate)
            await store.refreshEvents(for: refreshDate)
            guard !Task.isCancelled else { return }
            let loadedText = store.dayTexts[DateFormatting.normalizeToDay(refreshDate)] ?? ""
            if text.isEmpty && !loadedText.isEmpty {
                text = loadedText
            }
            colorMap = store.colorMap(for: refreshDate)
            unmatchedEvents = store.unmatchedEvents(for: refreshDate)
        }
    }
}
