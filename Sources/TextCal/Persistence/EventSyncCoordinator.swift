import EventKit
import Foundation

/// Errors raised by the sync coordinator.
enum SyncError: Error, CustomStringConvertible {
    /// Post-sync verification found an unexpected number of events in EventKit.
    /// This can indicate a silent EventKit failure or a race with an external edit.
    case verificationFailed(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .verificationFailed(let expected, let actual):
            return "Sync verification failed: expected \(expected) events, found \(actual)"
        }
    }
}

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

        // Default calendar: create-before-delete for crash safety.
        //
        // Safety rationale: if the app is killed mid-sync, we want to leave
        // duplicates (self-healing on next sync) rather than deletions (unrecoverable).
        // Sequence:
        //   1. Snapshot existing events (capture recurring + non-recurring for later)
        //   2. Create all new events first
        //   3. Delete only the specifically-snapshotted old non-recurring events
        // A crash at step 2 leaves old events intact (no data loss).
        // A crash at step 3 leaves duplicates that will be reconciled on next sync.
        if let defaultCal = defaultCal {
            let existingEvents = await ekManager.managedEvents(for: date, calendarIdentifier: defaultCal.calendarIdentifier)
            let existingRecurring = existingEvents.filter { $0.hasRecurrenceRules }
            let existingNonRecurring = existingEvents.filter { !$0.hasRecurrenceRules }

            // Step 1: Create new events (skip those matching existing recurring occurrences)
            var expectedNewEventCount = 0
            for event in defaultCalEvents {
                if matchesExistingRecurring(event, existing: existingRecurring, date: date) {
                    continue
                }
                try await saveEventToKit(event, date: date, calendar: defaultCal, ekManager: ekManager)
                expectedNewEventCount += 1
            }

            // Step 2: Delete the previously-snapshotted non-recurring events.
            // Only delete events we captured before creating new ones — this
            // guarantees we never delete a newly-created event, even if
            // titles/times happen to coincide.
            if !existingNonRecurring.isEmpty {
                try await ekManager.removeSpecificEvents(existingNonRecurring)
            }

            // Step 3: Verification pass. Re-fetch and confirm the final
            // non-recurring count matches what we expected to create. A
            // mismatch indicates EventKit silently dropped or duplicated
            // something — surface it so the caller can retry or alert.
            let finalEvents = await ekManager.managedEvents(for: date, calendarIdentifier: defaultCal.calendarIdentifier)
            let finalNonRecurring = finalEvents.filter { !$0.hasRecurrenceRules }
            if finalNonRecurring.count != expectedNewEventCount {
                throw SyncError.verificationFailed(
                    expected: expectedNewEventCount,
                    actual: finalNonRecurring.count
                )
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
