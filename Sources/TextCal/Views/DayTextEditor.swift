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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Autocomplete suggestions bar
            AutocompleteSuggestionsView(suggestions: autocompleteSuggestions) { suggestion in
                applySuggestion(suggestion)
            }

            SyntaxHighlightingTextView(
                text: $text,
                colorMap: colorMap,
                unmatchedEvents: unmatchedEvents,
                conflictingTitles: detectConflicts(in: text),
                eventsOnly: eventsOnly,
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

            // Unmatched EventKit events (from other apps)
            if !unmatchedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.eventsFromOtherCalendars)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(unmatchedEvents.enumerated()), id: \.offset) { _, info in
                        unmatchedEventLine(info)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
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
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !unmatchedEvents.isEmpty
    }

    @ViewBuilder
    private func unmatchedEventLine(_ info: EventLineInfo) -> some View {
        let calColor = info.calendarColor
        if let match = LineParser.parseEventLine(info.text) {
            (Text(match.timeText)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(calColor)
            + Text(match.separator + match.title)
                .font(.system(.body, design: .rounded)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("From other calendar: \(info.text)")
        } else if let match = LineParser.parseAllDayLine(info.text) {
            (Text("★ ")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(calColor)
            + Text(match.title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("From other calendar: \(info.text)")
        } else {
            Text(info.text)
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("From other calendar: \(info.text)")
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
            hasLoaded = true
        }
    }
}
