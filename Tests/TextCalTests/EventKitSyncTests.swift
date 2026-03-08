import Testing
import Foundation
@testable import TextCalKit

@Suite("EventKitSync Tests")
struct EventKitSyncTests {
    @Test("Converts daily recurrence to EKRecurrenceRule")
    func dailyRecurrence() {
        let rule = RecurrenceRule(frequency: .daily, rawText: "(daily)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .daily)
        #expect(ekRule?.interval == 1)
    }

    @Test("Converts weekday recurrence to EKRecurrenceRule with 5 days")
    func weekdayRecurrence() {
        let rule = RecurrenceRule(frequency: .weekdays, rawText: "(every weekday)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .weekly)
        #expect(ekRule?.daysOfTheWeek?.count == 5)
    }

    @Test("Converts weekly Tuesday recurrence")
    func weeklyTuesday() {
        let rule = RecurrenceRule(frequency: .weekly(weekday: 3), rawText: "(every Tuesday)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .weekly)
        #expect(ekRule?.interval == 1)
        #expect(ekRule?.daysOfTheWeek?.count == 1)
    }

    @Test("Converts biweekly recurrence")
    func biweeklyRecurrence() {
        let rule = RecurrenceRule(frequency: .biweekly(weekday: 2), rawText: "(every 2 weeks)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .weekly)
        #expect(ekRule?.interval == 2)
    }

    @Test("Converts monthly recurrence")
    func monthlyRecurrence() {
        let rule = RecurrenceRule(frequency: .monthly(day: 15), rawText: "(monthly 15th)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .monthly)
        #expect(ekRule?.daysOfTheMonth == [15])
    }

    @Test("Converts yearly recurrence")
    func yearlyRecurrence() {
        let rule = RecurrenceRule(frequency: .yearly(month: 3, day: 15), rawText: "(yearly)")
        let ekRule = EventKitSync.ekRecurrenceRule(from: rule)
        #expect(ekRule != nil)
        #expect(ekRule?.frequency == .yearly)
        #expect(ekRule?.interval == 1)
    }
}
