import SwiftUI

struct DayTextEditor: View {
    let date: Date
    var eventsOnly: Bool = false
    @Environment(CalendarStore.self) private var store
    @State private var text: String = ""
    @State private var colorMap: [EventColorKey: Color] = [:]
    @State private var unmatchedEvents: [EventLineInfo] = []
    @State private var refreshTask: Task<Void, Never>?
    @State private var showingTemplates = false
    @State private var autocompleteSuggestions: [AutocompleteSuggestion] = []
    @State private var calendarNames: [String] = []
    @State private var hasLoaded = false
    @State private var adoptedUnmatchedKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if eventsOnly {
                // Read-only filtered view: only shows event lines, collapsed layout
                StyledTextView(
                    text: text,
                    colorMap: colorMap,
                    conflictingTitles: detectConflicts(in: text),
                    eventsOnly: true,
                    calendarNames: calendarNames
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
                .frame(minHeight: 44)
                .accessibilityLabel(hasContent
                    ? "Events for \(DateFormatting.headerString(for: date))"
                    : "No events for \(DateFormatting.headerString(for: date))")
            } else {
                // Autocomplete suggestions bar
                AutocompleteSuggestionsView(suggestions: autocompleteSuggestions) { suggestion in
                    applySuggestion(suggestion)
                }

                SyntaxHighlightingTextView(
                    text: $text,
                    colorMap: colorMap,
                    unmatchedEvents: [],
                    conflictingTitles: detectConflicts(in: text),
                    eventsOnly: false,
                    calendarNames: calendarNames,
                    placeholder: "Type events like 9:00 AM - Meeting, or just write...",
                    onTextChange: { newValue in
                        store.update(date: date, text: newValue)
                        updateAutocompleteSuggestions()
                    }
                )
                .frame(minHeight: hasContent ? 44 : 44)
                .accessibilityLabel(hasContent
                    ? "Events and notes for \(DateFormatting.headerString(for: date))"
                    : "No events for \(DateFormatting.headerString(for: date))")
                .accessibilityHint("Edit events or notes")
            }
        }
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
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Text(Strings.done)
                }
                .fontWeight(.medium)
            }
        }
        .sheet(isPresented: $showingTemplates) {
            TemplatePickerView(
                templateStore: store.templateStore,
                onInsert: { templateText in
                    insertTemplate(templateText)
                }
            )
        }
        .onAppear {
            refreshState()
            loadCalendarNames()
        }
    }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            adoptUnmatchedEvents()
            hasLoaded = true
        }
    }

    /// Adopt unmatched EventKit events by appending their text lines into the editable text.
    /// Each event is only adopted once per session (tracked by adoptedUnmatchedKeys).
    private func adoptUnmatchedEvents() {
        guard !unmatchedEvents.isEmpty else { return }

        var newLines: [String] = []
        for info in unmatchedEvents {
            // Use the event text as a dedup key
            let eventKey = info.text
            guard !adoptedUnmatchedKeys.contains(eventKey) else { continue }
            adoptedUnmatchedKeys.insert(eventKey)
            newLines.append(info.text)
        }

        guard !newLines.isEmpty else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = trimmed.isEmpty ? "" : "\n"
        text = trimmed + separator + newLines.joined(separator: "\n")
        store.update(date: date, text: text)
    }
}
