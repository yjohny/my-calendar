import SwiftUI

/// A pre-parsed line for efficient rendering
private enum ParsedLine {
    case blank
    case allDay(AllDayMatch, calendarName: String?)
    case event(EventLineMatch, calendarName: String?)
    case note(String)
    case journal(String)
}

/// Displays day text with styling: event lines get color accents, journal text is plain.
/// Lines render in document order (interleaved events + journal).
struct StyledTextView: View {
    let text: String
    var colorMap: [EventColorKey: Color] = [:]
    var unmatchedEvents: [EventLineInfo] = []
    var conflictingTitles: Set<String> = []
    var eventsOnly: Bool = false
    var calendarNames: [String] = []
    /// Called when the user chooses "Move to..." on an event line.
    /// Parameters: (lineIndex, targetDate)
    var onMoveEvent: ((Int, Date) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    /// Pre-parse lines once per data change, not on every render
    private var parsedLines: [(Int, ParsedLine)] {
        text.components(separatedBy: "\n").enumerated().map { index, line in
            let (displayLine, calName) = stripCalendarPrefix(line)
            let trimmed = displayLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return (index, .blank)
            } else if let match = LineParser.parseAllDayLine(displayLine) {
                return (index, .allDay(match, calendarName: calName))
            } else if let match = LineParser.parseEventLine(displayLine) {
                return (index, .event(match, calendarName: calName))
            } else if displayLine.hasPrefix("  ") {
                return (index, .note(displayLine))
            } else {
                return (index, .journal(displayLine))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Render user's text in document order
            ForEach(parsedLines, id: \.0) { index, parsed in
                parsedLineView(parsed, lineIndex: index)
            }
            // Append any EventKit events not in user's text
            if !unmatchedEvents.isEmpty {
                Text(Strings.eventsFromOtherCalendars)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(unmatchedEvents.enumerated()), id: \.offset) { _, info in
                styledLine(info.text, overrideColor: info.calendarColor)
                    .accessibilityLabel("From other calendar: \(info.text)")
            }
        }
    }

    @ViewBuilder
    private func parsedLineView(_ parsed: ParsedLine, lineIndex: Int) -> some View {
        switch parsed {
        case .blank:
            if !eventsOnly {
                Text(" ")
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .allDay(let match, let calName):
            let color = lookupColor(title: match.title, isAllDay: true) ?? Color.orange
            allDayView(match: match, calendarColor: color, calendarName: calName)
                .modifier(MoveEventContextMenu(lineIndex: lineIndex, onMoveEvent: onMoveEvent))
        case .event(let match, let calName):
            let color = lookupColor(
                title: match.title,
                hour: match.timeComponents.hour,
                minute: match.timeComponents.minute
            ) ?? Color.accentColor
            eventView(match: match, calendarColor: color, calendarName: calName)
                .modifier(MoveEventContextMenu(lineIndex: lineIndex, onMoveEvent: onMoveEvent))
        case .note(let text):
            if !eventsOnly {
                Text(text)
                    .font(.system(.body, design: .rounded))
                    .italic()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .journal(let text):
            if !eventsOnly {
                markdownText(text)
                    .font(.system(.body, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func styledLine(_ line: String, overrideColor: Color? = nil) -> some View {
        // Strip [CalendarName] suffix/prefix for display (we show color instead)
        let (displayLine, calName) = stripCalendarPrefix(line)

        if displayLine.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(" ")
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let match = LineParser.parseAllDayLine(displayLine) {
            let color = overrideColor ?? lookupColor(title: match.title, isAllDay: true) ?? Color.orange
            allDayView(match: match, calendarColor: color, calendarName: calName)
        } else if let match = LineParser.parseEventLine(displayLine) {
            let color = overrideColor ?? lookupColor(
                title: match.title,
                hour: match.timeComponents.hour,
                minute: match.timeComponents.minute
            ) ?? Color.accentColor
            eventView(match: match, calendarColor: color, calendarName: calName)
        } else if displayLine.hasPrefix("  ") {
            Text(displayLine)
                .font(.system(.body, design: .rounded))
                .italic()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(displayLine)
                .font(.system(.body, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Look up calendar color from EventKit color map, adjusted for contrast
    private func lookupColor(title: String, hour: Int? = nil, minute: Int? = nil, isAllDay: Bool = false) -> Color? {
        let key = EventColorKey(title: title, hour: hour, minute: minute, isAllDay: isAllDay)
        guard let color = colorMap[key] else { return nil }
        return ensureContrast(color)
    }

    /// Ensure a color has sufficient contrast against the current background
    private func ensureContrast(_ color: Color) -> Color {
        // In dark mode, very dark colors are hard to read; in light mode, very light colors are hard to read
        let resolved = color.resolve(in: .init())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        if colorScheme == .dark && luminance < 0.3 {
            // Too dark for dark mode — lighten by blending toward white
            let boost = 0.4
            return Color(
                red: min(r + boost, 1.0),
                green: min(g + boost, 1.0),
                blue: min(b + boost, 1.0)
            )
        } else if colorScheme == .light && luminance > 0.85 {
            // Too light for light mode — darken by scaling down
            let factor = 0.6
            return Color(red: r * factor, green: g * factor, blue: b * factor)
        }
        return color
    }

    /// Check if a calendar name doesn't match any known calendar (case-insensitive)
    private func isUnknownCalendar(_ name: String) -> Bool {
        guard !calendarNames.isEmpty else { return false }
        return !calendarNames.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Returns the parenthesized text if it looks like a failed recurrence attempt, nil otherwise
    private func unrecognizedRecurrenceText(_ title: String, _ recurrence: RecurrenceRule?) -> String? {
        guard recurrence == nil else { return nil }
        guard let parenMatch = title.firstMatch(of: /\(([^)]+)\)\s*$/) else { return nil }
        let content = String(parenMatch.1)
        guard TimePatterns.looksLikeRecurrence(content) else { return nil }
        return String(parenMatch.0)
    }

    /// Render text with basic markdown formatting (bold, italic, strikethrough)
    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Strip `[CalendarName]` suffix or prefix from a line for display purposes
    private func stripCalendarPrefix(_ line: String) -> (line: String, calendarName: String?) {
        // Try suffix first (new format)
        if let result = LineParser.extractCalendarSuffix(line) {
            return (result.remainder, result.calendarName)
        }
        // Fall back to prefix (legacy format)
        if let result = LineParser.extractCalendarPrefix(line) {
            return (result.remainder, result.calendarName)
        }
        return (line, nil)
    }

    @ViewBuilder
    private func allDayView(match: AllDayMatch, calendarColor: Color, calendarName: String? = nil) -> some View {
        let result: Text = {
            var t = Text("★ ")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(calendarColor)
            + Text(match.title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
            if let recurrence = match.recurrence {
                t = t + Text("  " + recurrence.rawText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let warning = unrecognizedRecurrenceText(match.title, match.recurrence) {
                t = t + Text("  " + warning)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
            if let calName = calendarName {
                let isUnknown = isUnknownCalendar(calName)
                t = t + Text("  \(calName)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(isUnknown ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary.opacity(0.6)))
            }
            return t
        }()
        let isRecurring = match.recurrence != nil
        let label = "All day event: \(match.title)" + (isRecurring ? ", repeating" : "") + (calendarName.map { ", calendar \($0)" } ?? "")
        result
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isRecurring ? 0.7 : 1.0)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private func eventView(match: EventLineMatch, calendarColor: Color, calendarName: String? = nil) -> some View {
        let hasConflict = conflictingTitles.contains(match.title)
        let result: Text = {
            var t = Text(match.timeText)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(calendarColor)

            if let endTime = match.endTimeText {
                t = t + Text("–")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(calendarColor.opacity(0.7))
                + Text(endTime)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(calendarColor.opacity(0.7))
            }

            t = t + Text(match.separator + match.title)
                .font(.system(.body, design: .rounded))

            if let recurrence = match.recurrence {
                t = t + Text("  " + recurrence.rawText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let warning = unrecognizedRecurrenceText(match.title, match.recurrence) {
                t = t + Text("  " + warning)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
            if let calName = calendarName {
                let isUnknown = isUnknownCalendar(calName)
                t = t + Text("  \(calName)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(isUnknown ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary.opacity(0.6)))
            }
            if hasConflict {
                t = t + Text("  ⚠")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
            return t
        }()
        let isRecurring = match.recurrence != nil
        let label = "\(match.timeText) \(match.title)" + (isRecurring ? ", repeating" : "") + (hasConflict ? ", overlaps with another event" : "") + (calendarName.map { ", calendar \($0)" } ?? "")
        result
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isRecurring ? 0.7 : 1.0)
            .accessibilityLabel(label)
    }
}

/// Adds a "Move to..." context menu to event lines for text-native event moving.
/// Long-press an event → pick a date → the line is removed from this day and appended to the target day.
private struct MoveEventContextMenu: ViewModifier {
    let lineIndex: Int
    let onMoveEvent: ((Int, Date) -> Void)?
    @State private var showingDatePicker = false
    @State private var targetDate = DateFormatting.today

    func body(content: Content) -> some View {
        if onMoveEvent != nil {
            content
                .contextMenu {
                    Button {
                        // Tomorrow
                        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: DateFormatting.today) {
                            onMoveEvent?(lineIndex, tomorrow)
                        }
                    } label: {
                        Label(Strings.moveToTomorrow, systemImage: "arrow.right")
                    }
                    Button {
                        showingDatePicker = true
                    } label: {
                        Label(Strings.moveToDate, systemImage: "calendar")
                    }
                }
                .sheet(isPresented: $showingDatePicker) {
                    NavigationStack {
                        DatePicker(
                            Strings.moveToDate,
                            selection: $targetDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle(Strings.moveToDate)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Strings.cancel) { showingDatePicker = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(Strings.done) {
                                    onMoveEvent?(lineIndex, targetDate)
                                    showingDatePicker = false
                                }
                            }
                        }
                    }
                }
        } else {
            content
        }
    }
}
