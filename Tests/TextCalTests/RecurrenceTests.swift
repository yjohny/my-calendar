import Testing
import Foundation
@testable import TextCalKit

@Suite("Recurrence Tests")
struct RecurrenceTests {
    // MARK: - Parsing

    @Test("Parses (daily) recurrence")
    func parseDaily() {
        let rule = TimePatterns.parseRecurrence("daily")
        #expect(rule != nil)
        if case .daily = rule?.frequency {} else {
            Issue.record("Expected daily")
        }
    }

    @Test("Parses (every weekday) recurrence")
    func parseWeekdays() {
        let rule = TimePatterns.parseRecurrence("every weekday")
        #expect(rule != nil)
        if case .weekdays = rule?.frequency {} else {
            Issue.record("Expected weekdays")
        }
    }

    @Test("Parses (every Tuesday) recurrence")
    func parseWeekly() {
        let rule = TimePatterns.parseRecurrence("every Tuesday")
        #expect(rule != nil)
        if case .weekly(let weekday) = rule?.frequency {
            #expect(weekday == 3) // Tuesday = 3 in Calendar
        } else {
            Issue.record("Expected weekly")
        }
    }

    @Test("Parses (monthly 1st) recurrence")
    func parseMonthly() {
        let rule = TimePatterns.parseRecurrence("monthly 1st")
        #expect(rule != nil)
        if case .monthly(let day) = rule?.frequency {
            #expect(day == 1)
        } else {
            Issue.record("Expected monthly")
        }
    }

    @Test("Parses (monthly 15th) recurrence")
    func parseMonthly15th() {
        let rule = TimePatterns.parseRecurrence("monthly 15th")
        #expect(rule != nil)
        if case .monthly(let day) = rule?.frequency {
            #expect(day == 15)
        } else {
            Issue.record("Expected monthly")
        }
    }

    @Test("Parses (biweekly) recurrence")
    func parseBiweekly() {
        let rule = TimePatterns.parseRecurrence("biweekly")
        #expect(rule != nil)
        if case .biweekly = rule?.frequency {} else {
            Issue.record("Expected biweekly")
        }
    }

    @Test("Unknown recurrence returns nil")
    func parseUnknown() {
        let rule = TimePatterns.parseRecurrence("every full moon")
        #expect(rule == nil)
    }

    // MARK: - Event line with recurrence

    @Test("Event line extracts recurrence")
    func eventWithRecurrence() {
        let result = LineParser.parse("9:00 AM - Standup (every weekday)")
        guard case .event(let time, _, let title, let recurrence, _, _) = result else {
            Issue.record("Expected event, got \(result)")
            return
        }
        #expect(time.hour == 9)
        #expect(title == "Standup")
        #expect(recurrence != nil)
        if case .weekdays = recurrence?.frequency {} else {
            Issue.record("Expected weekdays recurrence")
        }
    }

    @Test("Event line without recurrence has nil recurrence")
    func eventWithoutRecurrence() {
        let result = LineParser.parse("9:00 AM - Standup")
        guard case .event(_, _, _, let recurrence, _, _) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(recurrence == nil)
    }

    // MARK: - Rule application

    @Test("Daily rule applies to every date after source")
    func dailyApplies() {
        let rule = RecurrenceRule(frequency: .daily, rawText: "(daily)")
        let calendar = Calendar.current
        let source = makeDate(year: 2026, month: 3, day: 9) // Monday
        let nextDay = calendar.date(byAdding: .day, value: 1, to: source)!
        let weekLater = calendar.date(byAdding: .day, value: 7, to: source)!
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: source)!

        #expect(rule.appliesTo(date: source, sourceDate: source) == true)
        #expect(rule.appliesTo(date: nextDay, sourceDate: source) == true)
        #expect(rule.appliesTo(date: weekLater, sourceDate: source) == true)
        #expect(rule.appliesTo(date: dayBefore, sourceDate: source) == false)
    }

    @Test("Weekday rule skips weekends")
    func weekdayRule() {
        let rule = RecurrenceRule(frequency: .weekdays, rawText: "(every weekday)")
        let monday = makeDate(year: 2026, month: 3, day: 9)
        let saturday = makeDate(year: 2026, month: 3, day: 14)
        let sunday = makeDate(year: 2026, month: 3, day: 15)
        let nextMonday = makeDate(year: 2026, month: 3, day: 16)

        #expect(rule.appliesTo(date: monday, sourceDate: monday) == true)
        #expect(rule.appliesTo(date: saturday, sourceDate: monday) == false)
        #expect(rule.appliesTo(date: sunday, sourceDate: monday) == false)
        #expect(rule.appliesTo(date: nextMonday, sourceDate: monday) == true)
    }

    @Test("Weekly rule applies on correct weekday")
    func weeklyRule() {
        let rule = RecurrenceRule(frequency: .weekly(weekday: 3), rawText: "(every Tuesday)")
        let tuesday = makeDate(year: 2026, month: 3, day: 10) // Tuesday
        let wednesday = makeDate(year: 2026, month: 3, day: 11)
        let nextTuesday = makeDate(year: 2026, month: 3, day: 17)

        #expect(rule.appliesTo(date: tuesday, sourceDate: tuesday) == true)
        #expect(rule.appliesTo(date: wednesday, sourceDate: tuesday) == false)
        #expect(rule.appliesTo(date: nextTuesday, sourceDate: tuesday) == true)
    }

    @Test("Parses (yearly) recurrence")
    func parseYearly() {
        let rule = TimePatterns.parseRecurrence("yearly")
        #expect(rule != nil)
        if case .yearly = rule?.frequency {} else {
            Issue.record("Expected yearly")
        }
    }

    @Test("Parses (annually) recurrence")
    func parseAnnually() {
        let rule = TimePatterns.parseRecurrence("annually")
        #expect(rule != nil)
        if case .yearly = rule?.frequency {} else {
            Issue.record("Expected yearly")
        }
    }

    @Test("Parses (every year) recurrence")
    func parseEveryYear() {
        let rule = TimePatterns.parseRecurrence("every year")
        #expect(rule != nil)
        if case .yearly = rule?.frequency {} else {
            Issue.record("Expected yearly")
        }
    }

    @Test("Yearly rule applies on correct month and day")
    func yearlyRule() {
        let rule = RecurrenceRule(frequency: .yearly(month: 3, day: 15), rawText: "(yearly)")
        let source = makeDate(year: 2026, month: 3, day: 15)
        let nextYear = makeDate(year: 2027, month: 3, day: 15)
        let wrongDay = makeDate(year: 2027, month: 3, day: 16)
        let wrongMonth = makeDate(year: 2027, month: 4, day: 15)

        #expect(rule.appliesTo(date: source, sourceDate: source) == true)
        #expect(rule.appliesTo(date: nextYear, sourceDate: source) == true)
        #expect(rule.appliesTo(date: wrongDay, sourceDate: source) == false)
        #expect(rule.appliesTo(date: wrongMonth, sourceDate: source) == false)
    }

    @Test("Monthly rule applies on correct day of month")
    func monthlyRule() {
        let rule = RecurrenceRule(frequency: .monthly(day: 15), rawText: "(monthly 15th)")
        let source = makeDate(year: 2026, month: 3, day: 15)
        let april15 = makeDate(year: 2026, month: 4, day: 15)
        let april16 = makeDate(year: 2026, month: 4, day: 16)

        #expect(rule.appliesTo(date: source, sourceDate: source) == true)
        #expect(rule.appliesTo(date: april15, sourceDate: source) == true)
        #expect(rule.appliesTo(date: april16, sourceDate: source) == false)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
}
