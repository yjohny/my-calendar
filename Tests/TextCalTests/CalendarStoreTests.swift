import Testing
import Foundation
@testable import TextCalKit

@Suite("CalendarStore Tests")
@MainActor
struct CalendarStoreTests {
    @Test("Empty store returns empty journal text for any date")
    func emptyStore() {
        let store = CalendarStore()
        let text = store.journalText(for: Date())
        #expect(text == "")
    }

    @Test("Update journal stores text for a date")
    func updateStoresJournal() {
        let store = CalendarStore()
        let date = Date()
        store.updateJournal(date: date, text: "Had a great day.")
        #expect(store.journalText(for: date) == "Had a great day.")
    }

    @Test("Update journal with empty text removes the entry")
    func updateRemovesEmpty() {
        let store = CalendarStore()
        let date = Date()
        store.updateJournal(date: date, text: "Some content")
        #expect(store.journalText(for: date) == "Some content")

        store.updateJournal(date: date, text: "   ")
        #expect(store.journalText(for: date) == "")
    }

    @Test("Normalizes dates to midnight for journal")
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

        store.updateJournal(date: afternoon, text: "Afternoon note")
        #expect(store.journalText(for: morning) == "Afternoon note")
    }

    @Test("Display text shows journal when no events")
    func displayTextJournalOnly() {
        let store = CalendarStore()
        let date = Date()
        store.updateJournal(date: date, text: "Just journaling.")
        let display = store.displayText(for: date)
        #expect(display == "Just journaling.")
    }

    @Test("Update separates journal from events")
    func updateSeparatesContent() {
        let store = CalendarStore()
        let date = Date()
        // Without EventKit configured, events won't sync but journal should be extracted
        store.update(date: date, text: "9:00 AM - Meeting\nHad a good day.")
        #expect(store.journalText(for: date) == "Had a good day.")
    }
}
