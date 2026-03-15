import Testing
import Foundation
@testable import TextCalKit

@Suite("Search Tests")
@MainActor
struct SearchTests {

    private func makeStore(with entries: [(Date, String)]) -> CalendarStore {
        let store = CalendarStore()
        for (date, text) in entries {
            store.update(date: date, text: text)
        }
        return store
    }

    private func date(year: Int = 2026, month: Int = 3, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    @Test("Empty query returns no results")
    func emptyQuery() {
        let store = makeStore(with: [(date(day: 1), "9:00 AM - Meeting")])
        let results = store.searchDayTexts(query: "")
        #expect(results.isEmpty)
    }

    @Test("Whitespace-only query returns no results")
    func whitespaceQuery() {
        let store = makeStore(with: [(date(day: 1), "9:00 AM - Meeting")])
        let results = store.searchDayTexts(query: "   ")
        #expect(results.isEmpty)
    }

    @Test("Case-insensitive matching")
    func caseInsensitive() {
        let store = makeStore(with: [(date(day: 1), "9:00 AM - Team Meeting")])
        let results = store.searchDayTexts(query: "team meeting")
        #expect(results.count == 1)
        #expect(results[0].matchingLines == ["9:00 AM - Team Meeting"])
    }

    @Test("Case-insensitive matching with uppercase query")
    func caseInsensitiveUppercase() {
        let store = makeStore(with: [(date(day: 1), "had a great day")])
        let results = store.searchDayTexts(query: "GREAT")
        #expect(results.count == 1)
    }

    @Test("No match returns empty results")
    func noMatch() {
        let store = makeStore(with: [(date(day: 1), "9:00 AM - Meeting")])
        let results = store.searchDayTexts(query: "lunch")
        #expect(results.isEmpty)
    }

    @Test("Multiple matching lines within a single day")
    func multiLineMatch() {
        let store = makeStore(with: [
            (date(day: 1), "9:00 AM - Team Meeting\nHad a meeting with the team\n2:00 PM - Lunch")
        ])
        let results = store.searchDayTexts(query: "meeting")
        #expect(results.count == 1)
        #expect(results[0].matchingLines.count == 2)
    }

    @Test("Results sorted by date descending (most recent first)")
    func sortedByDateDescending() {
        let store = makeStore(with: [
            (date(day: 1), "Morning standup"),
            (date(day: 10), "Morning standup"),
            (date(day: 5), "Morning standup")
        ])
        let results = store.searchDayTexts(query: "standup")
        #expect(results.count == 3)
        #expect(results[0].date > results[1].date)
        #expect(results[1].date > results[2].date)
    }

    @Test("Search across multiple days returns only matching days")
    func multiDayPartialMatch() {
        let store = makeStore(with: [
            (date(day: 1), "9:00 AM - Meeting"),
            (date(day: 2), "Went for a walk"),
            (date(day: 3), "10:00 AM - Meeting with Bob")
        ])
        let results = store.searchDayTexts(query: "meeting")
        #expect(results.count == 2)
    }

    @Test("Search on empty store returns no results")
    func emptyStore() {
        let store = CalendarStore()
        let results = store.searchDayTexts(query: "anything")
        #expect(results.isEmpty)
    }

    @Test("Partial word matching works")
    func partialMatch() {
        let store = makeStore(with: [(date(day: 1), "9:00 AM - Standup meeting")])
        let results = store.searchDayTexts(query: "stand")
        #expect(results.count == 1)
    }
}
