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

    /// Fetch events for a specific date
    func events(for date: Date) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Fetch events for a date range
    func events(from start: Date, to end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
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
        calendar: EKCalendar? = nil
    ) -> EKEvent? {
        guard let cal = calendar ?? getOrCreateCalendar() else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = cal
        event.isAllDay = isAllDay

        let dayCalendar = Calendar.current
        if isAllDay {
            event.startDate = dayCalendar.startOfDay(for: date)
            event.endDate = dayCalendar.startOfDay(for: date)
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

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event
        } catch {
            return nil
        }
    }

    /// Remove an event
    func removeEvent(_ event: EKEvent, span: EKSpan = .thisEvent) {
        try? store.remove(event, span: span, commit: true)
    }

    /// Remove non-recurring events in TextCal calendar for a given date.
    /// Recurring event occurrences are left untouched to avoid duplication bugs.
    func removeTextCalEvents(for date: Date) {
        guard let cal = getOrCreateCalendar() else { return }
        removeManagedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
    }

    /// Remove non-recurring events for a given date in the specified calendar.
    func removeManagedEvents(for date: Date, calendarIdentifier: String) {
        let dayEvents = events(for: date).filter { $0.calendar.calendarIdentifier == calendarIdentifier }
        for event in dayEvents {
            if event.hasRecurrenceRules {
                continue  // skip recurring occurrences
            }
            try? store.remove(event, span: .thisEvent, commit: true)
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

    /// Check if the user has granted calendar access
    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
}
