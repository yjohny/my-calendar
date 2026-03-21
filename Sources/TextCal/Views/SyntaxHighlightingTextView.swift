import SwiftUI
import UIKit

/// UITextView subclass that ensures layout is current before reporting character rects,
/// preventing RTIDocumentState firstRectForCharacterRange errors from stale geometry.
private class LayoutAwareTextView: UITextView {
    override func firstRect(for range: UITextRange) -> CGRect {
        layoutManager.ensureLayout(for: textContainer)
        let rect = super.firstRect(for: range)
        // Return caret rect as fallback if the system got a null/invalid rect
        if rect.isNull || rect.isInfinite {
            return caretRect(for: range.start)
        }
        return rect
    }
}

/// An always-editable text view with inline syntax highlighting for event lines.
/// Wraps UITextView to support attributed text editing — no mode switching needed.
struct SyntaxHighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    var colorMap: [EventColorKey: Color]
    var unmatchedEvents: [EventLineInfo]
    var conflictingTitles: Set<String>
    var eventsOnly: Bool
    var calendarNames: [String]
    var defaultCalendarName: String?
    var placeholder: String
    var onTextChange: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = LayoutAwareTextView()
        textView.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 2, left: 20, bottom: 8, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = false
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences

        // Set up placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.rounded(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 0
        placeholderLabel.tag = 999
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 2),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 20),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -20),
        ])

        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Update placeholder visibility
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasUnmatched = !unmatchedEvents.isEmpty
        if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
            placeholderLabel.isHidden = !isEmpty || hasUnmatched
        }

        // Only update text if it actually changed (prevents cursor jumping)
        if textView.text != text {
            coordinator.isUpdating = true
            let selectedRange = textView.selectedRange
            textView.text = text
            applyHighlighting(to: textView)
            // Restore cursor position
            let safeRange = NSRange(
                location: min(selectedRange.location, (textView.text as NSString).length),
                length: 0
            )
            textView.selectedRange = safeRange
            coordinator.isUpdating = false
        } else {
            // Re-apply highlighting (color map may have changed)
            coordinator.isUpdating = true
            let selectedRange = textView.selectedRange
            applyHighlighting(to: textView)
            textView.selectedRange = selectedRange
            coordinator.isUpdating = false
        }
    }

    fileprivate func applyHighlighting(to textView: UITextView) {
        let fullText = textView.text ?? ""
        guard !fullText.isEmpty else { return }

        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()

        // Reset to default style
        let bodySize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let defaultFont = UIFont.rounded(ofSize: bodySize)
        let defaultColor = UIColor.label

        storage.addAttribute(.font, value: defaultFont, range: fullRange)
        storage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)

        let nsString = fullText as NSString
        let lines = fullText.components(separatedBy: "\n")
        var location = 0

        for line in lines {
            let lineLength = (line as NSString).length
            let lineRange = NSRange(location: location, length: lineLength)
            let (displayLine, calendarName) = stripCalendarSyntax(line)

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Blank line — keep default
                if eventsOnly {
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: lineRange)
                }
            } else if let match = LineParser.parseAllDayLine(displayLine) {
                // All-day event: "* Title"
                let color = lookupUIColor(title: match.title, isAllDay: true) ?? UIColor.systemOrange
                // Color the star marker
                if let starRange = rangeOf("★", in: nsString, within: lineRange) ??
                   rangeOf("*", in: nsString, within: lineRange) {
                    storage.addAttribute(.foregroundColor, value: color, range: starRange)
                }
                // Bold the title
                let boldFont = UIFont.rounded(ofSize: bodySize, weight: .medium)
                storage.addAttribute(.font, value: boldFont, range: lineRange)

                if match.recurrence != nil {
                    storage.addAttribute(.foregroundColor, value: UIColor.label.withAlphaComponent(0.7), range: lineRange)
                }
                // Warn about unrecognized recurrence in the title
                highlightUnrecognizedRecurrence(match.title, match.recurrence, storage: storage, nsString: nsString, lineRange: lineRange)
                highlightUnknownCalendarName(calendarName, in: line, storage: storage, nsString: nsString, lineRange: lineRange)
                if conflictingTitles.contains(match.title) {
                    // We can't easily add inline warning icons in plain text, but we could underline
                }
            } else if let match = LineParser.parseEventLine(displayLine) {
                // Timed event: "9:00 AM - Title"
                let color = lookupUIColor(
                    title: match.title,
                    hour: match.timeComponents.hour,
                    minute: match.timeComponents.minute
                ) ?? UIColor.tintColor
                let monoFont = UIFont.monospacedDigitSystemFont(ofSize: bodySize, weight: .medium)

                // Use medium weight for the whole event line to distinguish from journal text
                let mediumFont = UIFont.rounded(ofSize: bodySize, weight: .medium)
                storage.addAttribute(.font, value: mediumFont, range: lineRange)

                // Find and style the time portion
                let timeText = match.timeText
                if let timeRange = rangeOf(timeText, in: nsString, within: lineRange) {
                    storage.addAttribute(.font, value: monoFont, range: timeRange)
                    storage.addAttribute(.foregroundColor, value: color, range: timeRange)
                }

                // Style end time if present
                if let endTime = match.endTimeText {
                    if let endRange = rangeOf(endTime, in: nsString, within: lineRange) {
                        storage.addAttribute(.font, value: monoFont, range: endRange)
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.85), range: endRange)
                    }
                    // Style the dash between times
                    let dashSearch = "\(timeText)–\(endTime)"
                    let altDashSearch = "\(timeText)-\(endTime)"
                    if let dashFullRange = rangeOf(dashSearch, in: nsString, within: lineRange) ??
                       rangeOf(altDashSearch, in: nsString, within: lineRange) {
                        let dashLoc = dashFullRange.location + (timeText as NSString).length
                        let dashRange = NSRange(location: dashLoc, length: 1)
                        if dashRange.location + dashRange.length <= storage.length {
                            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.85), range: dashRange)
                        }
                    }
                }

                // Style the separator between time and title with subtle event color
                let sepSearch = match.endTimeText != nil ? "\(match.endTimeText!)\(match.separator)" : "\(timeText)\(match.separator)"
                if let sepFullRange = rangeOf(sepSearch, in: nsString, within: lineRange) {
                    let sepStart = sepFullRange.location + (sepSearch as NSString).length - (match.separator as NSString).length
                    let sepRange = NSRange(location: sepStart, length: (match.separator as NSString).length)
                    if sepRange.location + sepRange.length <= storage.length {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.55), range: sepRange)
                    }
                }

                // Recurrence text in secondary color
                if let recurrence = match.recurrence {
                    let recText = recurrence.rawText
                    if let recRange = rangeOf(recText, in: nsString, within: lineRange) {
                        let captionFont = UIFont.rounded(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize)
                        storage.addAttribute(.font, value: captionFont, range: recRange)
                        storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: recRange)
                    }
                    // Fade the whole line slightly for recurring events
                    let currentColor = storage.attribute(.foregroundColor, at: lineRange.location, effectiveRange: nil) as? UIColor ?? UIColor.label
                    // Apply 0.7 opacity by adjusting alpha
                    storage.addAttribute(.foregroundColor, value: currentColor.withAlphaComponent(0.7), range: lineRange)
                    // Re-apply specific highlights that should keep their colors
                    if let timeRange = rangeOf(timeText, in: nsString, within: lineRange) {
                        storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.7), range: timeRange)
                    }
                }
                // Warn about unrecognized recurrence in the title
                highlightUnrecognizedRecurrence(match.title, match.recurrence, storage: storage, nsString: nsString, lineRange: lineRange)
                highlightUnknownCalendarName(calendarName, in: line, storage: storage, nsString: nsString, lineRange: lineRange)
            } else if line.hasPrefix("  ") {
                // Note line (indented) — italic + tertiary to distinguish from journal
                let italicFont = UIFont.italicSystemFont(ofSize: bodySize)
                storage.addAttribute(.font, value: italicFont, range: lineRange)
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: lineRange)
                if eventsOnly {
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: lineRange)
                }
            } else {
                // Journal text — slightly dimmer to distinguish from event lines
                storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: lineRange)
                if eventsOnly {
                    storage.addAttribute(.foregroundColor, value: UIColor.clear, range: lineRange)
                }
            }

            // Move past line + newline separator
            location += lineLength + 1  // +1 for "\n"
        }

        storage.endEditing()
    }

    private func lookupUIColor(title: String, hour: Int? = nil, minute: Int? = nil, isAllDay: Bool = false) -> UIColor? {
        let key = EventColorKey(title: title, hour: hour, minute: minute, isAllDay: isAllDay)
        guard let color = colorMap[key] else { return nil }
        let adjusted = ensureContrastColor(color)
        return UIColor(adjusted)
    }

    private func ensureContrastColor(_ color: Color) -> Color {
        let resolved = color.resolve(in: .init())
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        if colorScheme == .dark && luminance < 0.3 {
            let boost = 0.4
            return Color(
                red: min(r + boost, 1.0),
                green: min(g + boost, 1.0),
                blue: min(b + boost, 1.0)
            )
        } else if colorScheme == .light && luminance > 0.85 {
            let factor = 0.6
            return Color(red: r * factor, green: g * factor, blue: b * factor)
        }
        return color
    }

    /// Strip [CalendarName] suffix or prefix for highlighting purposes
    private func stripCalendarSyntax(_ line: String) -> (line: String, calendarName: String?) {
        if let result = LineParser.extractCalendarSuffix(line) {
            return (result.remainder, result.calendarName)
        }
        if let result = LineParser.extractCalendarPrefix(line) {
            return (result.remainder, result.calendarName)
        }
        return (line, nil)
    }

    /// Highlight [CalendarName] bracket syntax: hide for default calendar, orange for unknown
    private func highlightUnknownCalendarName(_ calendarName: String?, in line: String, storage: NSTextStorage, nsString: NSString, lineRange: NSRange) {
        guard let calName = calendarName else { return }
        let bracketText = "[\(calName)]"
        // Hide brackets for default calendar
        if let defName = defaultCalendarName,
           calName.localizedCaseInsensitiveCompare(defName) == .orderedSame {
            if let nsRange = rangeOf(bracketText, in: nsString, within: lineRange) {
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel.withAlphaComponent(0.3), range: nsRange)
                let captionFont = UIFont.rounded(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize)
                storage.addAttribute(.font, value: captionFont, range: nsRange)
            }
            return
        }
        // Check against known calendar names (case-insensitive)
        let matches = calendarNames.contains { $0.localizedCaseInsensitiveCompare(calName) == .orderedSame }
        guard !matches else { return }
        // Find the bracketed text in the original line
        if let nsRange = rangeOf(bracketText, in: nsString, within: lineRange) {
            storage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: nsRange)
        }
    }

    /// Highlight parenthesized text that looks like a failed recurrence attempt in orange
    private func highlightUnrecognizedRecurrence(_ title: String, _ recurrence: RecurrenceRule?, storage: NSTextStorage, nsString: NSString, lineRange: NSRange) {
        // Only flag if no valid recurrence was parsed
        guard recurrence == nil else { return }
        // Check if the title contains parenthesized text at the end that looks like a recurrence
        guard let parenMatch = title.firstMatch(of: /\(([^)]+)\)\s*$/) else { return }
        let content = String(parenMatch.1)
        guard TimePatterns.looksLikeRecurrence(content) else { return }
        let parenText = String(parenMatch.0)
        if let nsRange = rangeOf(parenText, in: nsString, within: lineRange) {
            storage.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: nsRange)
        }
    }

    private func rangeOf(_ needle: String, in haystack: NSString, within range: NSRange) -> NSRange? {
        let result = haystack.range(of: needle, options: [], range: range)
        return result.location != NSNotFound ? result : nil
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var isUpdating = false
        weak var textView: UITextView?

        init(parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            let newText = textView.text ?? ""
            parent.text = newText
            parent.onTextChange?(newText)

            // Re-apply highlighting after edit
            isUpdating = true
            let selected = textView.selectedRange
            parent.applyHighlighting(to: textView)
            textView.selectedRange = selected
            isUpdating = false

            // Update placeholder
            let isEmpty = newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !isEmpty
            }

            // Invalidate intrinsic content size for auto-sizing
            textView.invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - UIFont helpers for rounded design

private extension UIFont {
    static func rounded(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let desc = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if let rounded = desc.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }
}
