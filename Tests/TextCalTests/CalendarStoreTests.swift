import Testing
import Foundation
@testable import TextCalKit

@Suite("CalendarStore Tests")
@MainActor
struct CalendarStoreTests {
    @Test("Empty store returns empty text for any date")
    func emptyStore() {
        let store = CalendarStore()
        let text = store.text(for: Date())
        #expect(text == "")
    }

    @Test("Update stores text for a date")
    func updateStoresText() {
        let store = CalendarStore()
        let date = Date()
        store.update(date: date, text: "Hello world")
        #expect(store.text(for: date) == "Hello world")
    }

    @Test("Update with empty text removes the entry")
    func updateRemovesEmpty() {
        let store = CalendarStore()
        let date = Date()
        store.update(date: date, text: "Some content")
        #expect(store.text(for: date) == "Some content")

        store.update(date: date, text: "   ")
        #expect(store.text(for: date) == "")
    }

    @Test("Entries returns filled range with empty days")
    func entriesReturnsRange() {
        let store = CalendarStore()
        let calendar = Calendar.current
        let today = DateFormatting.today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: today)!

        store.update(date: today, text: "Today's note")

        let entries = store.entries(from: today, to: dayAfter)
        #expect(entries.count == 3)
        #expect(entries[0].rawText == "Today's note")
        #expect(entries[1].rawText == "")  // tomorrow, empty
        #expect(entries[2].rawText == "")  // day after, empty
    }

    @Test("Normalizes dates to midnight")
    func normalizesDate() {
        let store = CalendarStore()
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 14
        components.minute = 30
        let afternoon = Calendar.current.date(from: components)!

        components.hour = 8
        components.minute = 0
        let morning = Calendar.current.date(from: components)!

        store.update(date: afternoon, text: "Afternoon note")
        #expect(store.text(for: morning) == "Afternoon note")
    }
}
