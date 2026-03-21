import EventKit
import Foundation

/// Coordinates syncing parsed events to EventKit.
/// Extracted from CalendarStore to isolate sync logic from state management.
@MainActor
struct EventSyncCoordinator {

    /// Sync parsed event groups to EventKit for a given date.
    /// Default calendar events are deleted-and-recreated; override calendar events are create-only.
    static func syncEvents(
        date: Date,
        events: [ParsedEventGroup],
        ekManager: EventKitManager,
        calendarSettings: CalendarSettings?
    ) async throws {
        let defaultCal = await resolveDefaultCalendar(ekManager: ekManager, calendarSettings: calendarSettings)
        let defaultCalId = defaultCal?.calendarIdentifier

        var defaultCalEvents: [ParsedEventGroup] = []
        var overrideEvents: [(event: ParsedEventGroup, calendar: EKCalendar)] = []

        for event in events {
            if let name = event.calendarName,
               let cal = await ekManager.calendarByTitle(name),
               cal.calendarIdentifier != defaultCalId {
                overrideEvents.append((event, cal))
            } else {
                defaultCalEvents.append(event)
            }
        }

        // Default calendar: safe to delete-and-recreate (we own these events)
        if let defaultCal = defaultCal {
            let calId = defaultCal.calendarIdentifier
            let existingEvents = await ekManager.managedEvents(for: date, calendarIdentifier: calId)
            let existingRecurring = existingEvents.filter { $0.hasRecurrenceRules }

            try await ekManager.removeManagedEvents(for: date, calendarIdentifier: calId)

            for event in defaultCalEvents {
                if matchesExistingRecurring(event, existing: existingRecurring, date: date) {
                    continue
                }
                try await saveEventToKit(event, date: date, calendar: defaultCal, ekManager: ekManager)
            }
        }

        // Override calendars: create-only (never delete events we don't own)
        for (event, cal) in overrideEvents {
            let existingInCal = await ekManager.managedEvents(for: date, calendarIdentifier: cal.calendarIdentifier)
            if matchesExistingEvent(event, existing: existingInCal, date: date) {
                continue
            }
            try await saveEventToKit(event, date: date, calendar: cal, ekManager: ekManager)
        }
    }

    /// Resolve the user's default calendar (setting → TextCal fallback)
    static func resolveDefaultCalendar(ekManager: EventKitManager, calendarSettings: CalendarSettings?) async -> EKCalendar? {
        if let settingsId = calendarSettings?.defaultCalendarIdentifier,
           let cal = await ekManager.calendarForIdentifier(settingsId) {
            return cal
        }
        return await ekManager.getOrCreateCalendar()
    }

    /// Resolve the default calendar identifier
    static func resolveDefaultCalendarId(ekManager: EventKitManager, calendarSettings: CalendarSettings?) async -> String? {
        if let settingsId = calendarSettings?.defaultCalendarIdentifier,
           await ekManager.calendarForIdentifier(settingsId) != nil {
            return settingsId
        }
        if let textCal = await ekManager.getOrCreateCalendar() {
            return textCal.calendarIdentifier
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func saveEventToKit(_ event: ParsedEventGroup, date: Date, calendar: EKCalendar, ekManager: EventKitManager) async throws {
        let ekRule: EKRecurrenceRule?
        if let recurrence = event.recurrence {
            ekRule = EventKitSync.ekRecurrenceRule(from: recurrence)
        } else {
            ekRule = nil
        }
        let notes = event.notes.isEmpty ? nil : event.notes.joined(separator: "\n")
        try await ekManager.saveEvent(
            title: event.title,
            date: date,
            startTime: event.startTime,
            endTime: event.endTime,
            isAllDay: event.isAllDay,
            notes: notes,
            recurrenceRule: ekRule,
            calendar: calendar,
            alarmOffset: event.alarmOffset
        )
    }

    private static func matchesExistingEvent(_ parsed: ParsedEventGroup, existing: [EKEvent], date: Date) -> Bool {
        let cal = Calendar.current
        for ekEvent in existing {
            guard ekEvent.title == parsed.title else { continue }
            guard ekEvent.isAllDay == parsed.isAllDay else { continue }
            if parsed.isAllDay { return true }
            if let startTime = parsed.startTime {
                let ekComps = cal.dateComponents([.hour, .minute], from: ekEvent.startDate)
                guard ekComps.hour == startTime.hour && ekComps.minute == startTime.minute else { continue }
                if let endTime = parsed.endTime {
                    let ekEndComps = cal.dateComponents([.hour, .minute], from: ekEvent.endDate)
                    guard ekEndComps.hour == endTime.hour && ekEndComps.minute == endTime.minute else { continue }
                }
                return true
            }
        }
        return false
    }

    private static func matchesExistingRecurring(_ parsed: ParsedEventGroup, existing: [EKEvent], date: Date) -> Bool {
        let cal = Calendar.current
        for ekEvent in existing {
            guard ekEvent.title == parsed.title else { continue }
            guard ekEvent.isAllDay == parsed.isAllDay else { continue }
            if parsed.isAllDay { return true }
            if let startTime = parsed.startTime {
                let ekComps = cal.dateComponents([.hour, .minute], from: ekEvent.startDate)
                guard ekComps.hour == startTime.hour && ekComps.minute == startTime.minute else { continue }
                if let endTime = parsed.endTime {
                    let ekEndComps = cal.dateComponents([.hour, .minute], from: ekEvent.endDate)
                    guard ekEndComps.hour == endTime.hour && ekEndComps.minute == endTime.minute else { continue }
                }
                return true
            }
        }
        return false
    }
}
