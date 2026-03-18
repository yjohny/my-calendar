import EventKit
import Foundation

/// Wraps EKEventStore for calendar event CRUD operations
actor EventKitManager {
    let store = EKEventStore()
    private var textCalCalendar: EKCalendar?

    /// The name of the fallback calendar we create/use in EventKit
    private let calendarName = "TextCal"

    /// Returns all calendars the user can write to (for calendar picker UI)
    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    /// Look up a calendar by its identifier
    func calendarForIdentifier(_ id: String) -> EKCalendar? {
        store.calendars(for: .event).first { $0.calendarIdentifier == id }
    }

    /// Look up a calendar by title (case-insensitive)
    func calendarByTitle(_ title: String) -> EKCalendar? {
        store.calendars(for: .event).first { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }
    }

    /// Request access to calendar events
    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Get or create the TextCal calendar
    func getOrCreateCalendar() -> EKCalendar? {
        if let existing = textCalCalendar { return existing }

        // Look for existing TextCal calendar
        let calendars = store.calendars(for: .event)
        if let found = calendars.first(where: { $0.title == calendarName }) {
            textCalCalendar = found
            return found
        }

        // Create a new one
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName

        // Use the default calendar source (iCloud if available, otherwise local)
        if let defaultSource = store.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else if let localSource = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else {
            return nil
        }

        do {
            try store.saveCalendar(calendar, commit: true)
            textCalCalendar = calendar
            return calendar
        } catch {
            return nil
        }
    }

    /// Fetch events for a specific date, optionally excluding hidden calendars
    func events(for date: Date, excludingCalendars hidden: Set<String> = []) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var results = store.events(matching: predicate)
        if !hidden.isEmpty {
            results = results.filter { !hidden.contains($0.calendar.calendarIdentifier) }
        }
        return results.sorted { $0.startDate < $1.startDate }
    }

    /// Fetch events for a date range, optionally excluding hidden calendars
    func events(from start: Date, to end: Date, excludingCalendars hidden: Set<String> = []) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var results = store.events(matching: predicate)
        if !hidden.isEmpty {
            results = results.filter { !hidden.contains($0.calendar.calendarIdentifier) }
        }
        return results
    }

    /// Returns all calendars (writable and read-only) for the visibility picker
    func allCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    /// Create or update an event. Uses the provided calendar, or falls back to TextCal.
    @discardableResult
    func saveEvent(
        title: String,
        date: Date,
        startTime: DateComponents?,
        endTime: DateComponents?,
        isAllDay: Bool,
        notes: String?,
        recurrenceRule: EKRecurrenceRule?,
        calendar: EKCalendar? = nil,
        alarmOffset: TimeInterval? = nil
    ) throws -> EKEvent {
        guard let cal = calendar ?? getOrCreateCalendar() else {
            throw EventKitError.noCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = cal
        event.isAllDay = isAllDay

        let dayCalendar = Calendar.current
        if isAllDay {
            event.startDate = dayCalendar.startOfDay(for: date)
            // All-day events in EventKit require endDate to be the next day
            event.endDate = dayCalendar.date(byAdding: .day, value: 1, to: event.startDate) ?? event.startDate.addingTimeInterval(86400)
        } else if let start = startTime {
            var startComps = dayCalendar.dateComponents([.year, .month, .day], from: date)
            startComps.hour = start.hour
            startComps.minute = start.minute
            event.startDate = dayCalendar.date(from: startComps) ?? date

            if let end = endTime {
                var endComps = startComps
                endComps.hour = end.hour
                endComps.minute = end.minute
                event.endDate = dayCalendar.date(from: endComps) ?? event.startDate.addingTimeInterval(3600)
            } else {
                // Default 1 hour duration
                event.endDate = event.startDate.addingTimeInterval(3600)
            }
        }

        if let notes = notes, !notes.isEmpty {
            event.notes = notes
        }

        if let rule = recurrenceRule {
            event.recurrenceRules = [rule]
        }

        if let alarmOffset {
            event.addAlarm(EKAlarm(relativeOffset: alarmOffset))
        }

        try store.save(event, span: .thisEvent, commit: true)
        return event
    }

    enum EventKitError: Error {
        case noCalendar
    }

    /// Remove an event
    func removeEvent(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span, commit: true)
    }

    /// Remove non-recurring events in TextCal calendar for a given date.
    /// Recurring event occurrences are left untouched to avoid duplication bugs.
    func removeTextCalEvents(for date: Date) throws {
        guard let cal = getOrCreateCalendar() else {
            throw EventKitError.noCalendar
        }
        try removeManagedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
    }

    /// Remove non-recurring events for a given date in the specified calendar.
    /// Batches removals into a single commit for better performance.
    func removeManagedEvents(for date: Date, calendarIdentifier: String) throws {
        let dayEvents = events(for: date).filter { $0.calendar.calendarIdentifier == calendarIdentifier }
        var didRemove = false
        for event in dayEvents {
            if event.hasRecurrenceRules {
                continue  // skip recurring occurrences
            }
            try store.remove(event, span: .thisEvent, commit: false)
            didRemove = true
        }
        if didRemove {
            try store.commit()
        }
    }

    /// Fetch TextCal events for a specific date
    func textCalEvents(for date: Date) -> [EKEvent] {
        guard let cal = getOrCreateCalendar() else { return [] }
        return managedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
    }

    /// Fetch events for a specific date in the specified calendar
    func managedEvents(for date: Date, calendarIdentifier: String) -> [EKEvent] {
        events(for: date).filter { $0.calendar.calendarIdentifier == calendarIdentifier }
    }

    /// Search events across a date range, filtering by title (case-insensitive)
    func searchEvents(query: String, from start: Date, to end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let allEvents = store.events(matching: predicate)
        let lowered = query.lowercased()
        return allEvents.filter { ($0.title ?? "").lowercased().contains(lowered) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Check if the user has granted calendar access
    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
}
