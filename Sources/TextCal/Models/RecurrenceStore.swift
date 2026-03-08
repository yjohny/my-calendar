import Foundation

/// A single recurring event definition, extracted from a day's text
struct RecurringEvent: Equatable, Codable {
    /// The date where the user originally typed this event
    let sourceDate: Date
    /// The full original line text (e.g. "9:00 AM - Standup (every weekday)")
    let lineText: String
    /// The parsed recurrence rule
    let rule: RecurrenceRule

    /// Unique identity based on source date + line text
    var id: String {
        "\(sourceDate.timeIntervalSince1970)|\(lineText)"
    }
}

/// Exception: a specific date where a recurring event is skipped
struct RecurrenceException: Equatable, Codable {
    let eventId: String
    let date: Date
}

/// End override: stop a recurring event from a specific date onward
struct RecurrenceEnd: Equatable, Codable {
    let eventId: String
    let endDate: Date
}

/// Manages recurring events, their materialization on dates, and exceptions
@MainActor
@Observable
final class RecurrenceStore {
    /// All known recurring events, keyed by event ID
    private(set) var recurringEvents: [String: RecurringEvent] = [:]
    /// Dates to skip for specific recurring events
    private(set) var exceptions: Set<String> = []  // "eventId|dateInterval" format
    /// End dates for recurring events (stop generating after this)
    private(set) var endOverrides: [String: Date] = [:]  // eventId -> endDate

    /// Rebuild the recurring events index from all days in the store
    func rebuildIndex(from days: [Date: DayEntry]) {
        var newEvents: [String: RecurringEvent] = [:]

        for (date, entry) in days {
            let lines = entry.rawText.components(separatedBy: "\n")
            for line in lines {
                let parsed = LineParser.parse(line)
                let recurrence: RecurrenceRule?

                switch parsed {
                case .event(_, _, _, let r): recurrence = r
                case .allDay(_, let r): recurrence = r
                default: recurrence = nil
                }

                if let rule = recurrence {
                    let event = RecurringEvent(sourceDate: date, lineText: line, rule: resolveRule(rule, sourceDate: date))
                    newEvents[event.id] = event
                }
            }
        }

        // Remove exceptions/ends for events that no longer exist
        let validIds = Set(newEvents.keys)
        exceptions = exceptions.filter { key in
            let eventId = String(key.split(separator: "|").dropLast().joined(separator: "|"))
            return validIds.contains(eventId)
        }
        endOverrides = endOverrides.filter { validIds.contains($0.key) }

        recurringEvents = newEvents
    }

    /// Get the materialized recurring event lines for a specific date
    func materializedLines(for date: Date) -> [String] {
        let calendar = Calendar.current
        let normalizedDate = DateFormatting.normalizeToDay(date)
        var lines: [String] = []

        for (_, event) in recurringEvents {
            // Skip if this is the source date (already in the user's text)
            if calendar.isDate(normalizedDate, inSameDayAs: event.sourceDate) {
                continue
            }

            // Check end override
            if let endDate = endOverrides[event.id],
               calendar.compare(normalizedDate, to: endDate, toGranularity: .day) != .orderedAscending {
                continue
            }

            // Check exception
            let exceptionKey = "\(event.id)|\(normalizedDate.timeIntervalSince1970)"
            if exceptions.contains(exceptionKey) {
                continue
            }

            // Check if rule applies
            if event.rule.appliesTo(date: normalizedDate, sourceDate: event.sourceDate) {
                lines.append(event.lineText)
            }
        }

        return lines.sorted()
    }

    /// Add an exception (skip one occurrence)
    func addException(eventId: String, date: Date) {
        let normalizedDate = DateFormatting.normalizeToDay(date)
        let key = "\(eventId)|\(normalizedDate.timeIntervalSince1970)"
        exceptions.insert(key)
    }

    /// End a recurring event from a date onward
    func endRecurrence(eventId: String, from date: Date) {
        let normalizedDate = DateFormatting.normalizeToDay(date)
        endOverrides[eventId] = normalizedDate
    }

    /// Find the recurring event that matches a given line on a given date
    func findEvent(forLine line: String, on date: Date) -> RecurringEvent? {
        recurringEvents.values.first { $0.lineText == line }
    }

    /// Resolve a rule with weekday=0 sentinel to use the source date's weekday
    private func resolveRule(_ rule: RecurrenceRule, sourceDate: Date) -> RecurrenceRule {
        let calendar = Calendar.current
        let sourceWeekday = calendar.component(.weekday, from: sourceDate)

        switch rule.frequency {
        case .weekly(let weekday) where weekday == 0:
            return RecurrenceRule(frequency: .weekly(weekday: sourceWeekday), rawText: rule.rawText)
        case .biweekly(let weekday) where weekday == 0:
            return RecurrenceRule(frequency: .biweekly(weekday: sourceWeekday), rawText: rule.rawText)
        case .monthly(let day) where day == 0:
            let sourceDay = calendar.component(.day, from: sourceDate)
            return RecurrenceRule(frequency: .monthly(day: sourceDay), rawText: rule.rawText)
        default:
            return rule
        }
    }
}
