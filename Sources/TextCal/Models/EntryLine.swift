import Foundation

/// A parsed line from a day's text content.
/// Derived from raw text — never persisted directly.
enum EntryLine: Equatable {
    /// A line with a recognized time (and optional end time) and event title
    case event(time: DateComponents, endTime: DateComponents?, title: String, recurrence: RecurrenceRule?, calendarName: String?)
    /// An all-day event (lines starting with "* ")
    case allDay(title: String, recurrence: RecurrenceRule?, calendarName: String?)
    /// A continuation/note line (indented, follows an event)
    case eventNote(text: String)
    /// Freeform journal text
    case journal(text: String)
    /// An empty line
    case blank
}
