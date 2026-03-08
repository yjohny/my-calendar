import EventKit
import Foundation
import SwiftUI

/// Converts between our text-based event format and EventKit objects
enum EventKitSync {

    // MARK: - EKEvent → Text Line

    /// Render an EKEvent as a text line suitable for display
    static func textLine(from event: EKEvent) -> String {
        if event.isAllDay {
            return allDayLine(from: event)
        } else {
            return timedLine(from: event)
        }
    }

    /// Render an EKEvent as a text line, prepending `[CalendarTitle]` if it's not the default calendar.
    static func textLine(from event: EKEvent, defaultCalendarId: String?) -> String {
        let line = textLine(from: event)
        if let defaultId = defaultCalendarId, event.calendar.calendarIdentifier != defaultId {
            return "[\(event.calendar.title)] \(line)"
        }
        return line
    }

    /// Extract the calendar's color as a SwiftUI Color
    static func calendarColor(from event: EKEvent) -> Color {
        Color(cgColor: event.calendar.cgColor)
    }

    private static func allDayLine(from event: EKEvent) -> String {
        var line = "* \(event.title ?? "Event")"
        if let recurrenceText = recurrenceText(from: event) {
            line += " \(recurrenceText)"
        }
        return line
    }

    private static func timedLine(from event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let startStr = formatter.string(from: event.startDate)

        // Check if end time is meaningful (not just start + default 1hr)
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let hasEndTime = duration > 0 && duration != 3600

        var line: String
        if hasEndTime {
            let endStr = formatter.string(from: event.endDate)
            line = "\(startStr)-\(endStr) - \(event.title ?? "Event")"
        } else {
            line = "\(startStr) - \(event.title ?? "Event")"
        }

        if let recurrenceText = recurrenceText(from: event) {
            line += " \(recurrenceText)"
        }
        return line
    }

    /// Render notes as indented lines
    static func noteLines(from event: EKEvent) -> [String] {
        guard let notes = event.notes, !notes.isEmpty else { return [] }
        return notes.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "  \($0)" }
    }

    // MARK: - RecurrenceRule → Text

    private static func recurrenceText(from event: EKEvent) -> String? {
        guard let rule = event.recurrenceRules?.first else { return nil }

        switch rule.frequency {
        case .daily:
            if rule.daysOfTheWeek?.count == 5 {
                return "(every weekday)"
            }
            return "(daily)"

        case .weekly:
            if let days = rule.daysOfTheWeek, days.count == 1 {
                let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                let dayIndex = days[0].dayOfTheWeek.rawValue
                if dayIndex >= 1 && dayIndex <= 7 {
                    return "(every \(dayNames[dayIndex]))"
                }
            }
            if rule.interval == 2 {
                return "(every 2 weeks)"
            }
            return "(weekly)"

        case .monthly:
            if let days = rule.daysOfTheMonth, let day = days.first {
                return "(monthly \(ordinal(day.intValue)))"
            }
            return "(monthly)"

        case .yearly:
            return "(yearly)"

        @unknown default:
            return nil
        }
    }

    // MARK: - Text RecurrenceRule → EKRecurrenceRule

    /// Convert our RecurrenceRule to an EKRecurrenceRule
    static func ekRecurrenceRule(from rule: RecurrenceRule) -> EKRecurrenceRule? {
        switch rule.frequency {
        case .daily:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            )

        case .weekdays:
            let weekdays = [
                EKRecurrenceDayOfWeek(.monday),
                EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday),
                EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday),
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .weekly(let weekday):
            guard weekday >= 1 && weekday <= 7 else { return nil }
            let ekWeekdays: [EKWeekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let day = EKRecurrenceDayOfWeek(ekWeekdays[weekday - 1])
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: [day],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .biweekly(let weekday):
            guard weekday >= 1 && weekday <= 7 else { return nil }
            let ekWeekdays: [EKWeekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let day = EKRecurrenceDayOfWeek(ekWeekdays[weekday - 1])
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 2,
                daysOfTheWeek: [day],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .monthly(let day):
            guard day >= 1 && day <= 31 else { return nil }
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: day)],
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .yearly:
            return EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: 1,
                end: nil
            )
        }
    }

    // MARK: - Helpers

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
