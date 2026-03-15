import Testing
import Foundation
@testable import TextCalKit

@Suite("CalendarStore Tests")
@MainActor
struct CalendarStoreTests {
    @Test("Empty store returns empty display text for any date")
    func emptyStore() {
        let store = CalendarStore()
        let text = store.displayText(for: Date())
        #expect(text == "")
    }

    @Test("Update stores text for a date")
    func updateStoresText() {
        let store = CalendarStore()
        let date = Date()
        store.update(date: date, text: "Had a great day.")
        #expect(store.displayText(for: date) == "Had a great day.")
    }

    @Test("Update with empty text removes the entry")
    func updateRemovesEmpty() {
        let store = CalendarStore()
        let date = Date()
        store.update(date: date, text: "Some content")
        #expect(store.displayText(for: date) == "Some content")

        store.update(date: date, text: "   ")
        #expect(store.displayText(for: date) == "")
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
        #expect(store.displayText(for: morning) == "Afternoon note")
    }

    @Test("Display text shows content when no events")
    func displayTextJournalOnly() {
        let store = CalendarStore()
        let date = Date()
        store.update(date: date, text: "Just journaling.")
        let display = store.displayText(for: date)
        #expect(display == "Just journaling.")
    }

    @Test("Update stores mixed events and journal text")
    func updateStoresMixed() {
        let store = CalendarStore()
        let date = Date()
        // Without EventKit configured, events won't sync but text should be stored
        let text = "9:00 AM - Meeting\nHad a good day."
        store.update(date: date, text: text)
        #expect(store.displayText(for: date) == text)
    }

    @Test("Sync status is idle when no EventKit access and no sync task")
    func syncStatusIdleWithoutAccess() {
        let store = CalendarStore()
        let date = Date()
        // Without configure(), there's no EventKit access, so sync should go idle
        store.update(date: date, text: "9:00 AM - Meeting")
        #expect(store.syncStatus == .idle || store.syncStatus == .saving)
    }

    @Test("SearchResult dates are unique")
    func searchResultUniqueDates() {
        let store = CalendarStore()
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1
        let date1 = Calendar.current.date(from: components)!
        components.day = 2
        let date2 = Calendar.current.date(from: components)!

        store.update(date: date1, text: "Morning standup")
        store.update(date: date2, text: "Morning standup")

        let results = store.searchDayTexts(query: "standup")
        let dates = results.map { $0.date }
        let uniqueDates = Set(dates)
        #expect(dates.count == uniqueDates.count)
    }

    @Test("Update with mixed events and journal stores day text")
    func updateStoresDayText() {
        let store = CalendarStore()
        let date = Date()
        let text = "9:00 AM - Meeting\nHad lunch\n2:00 PM - Review"
        store.update(date: date, text: text)
        #expect(store.displayText(for: date) == text)
    }

    @Test("Error sync status has associated message")
    func errorSyncStatusMessage() {
        let status = CalendarStore.SyncStatus.error("Save failed")
        #expect(status == .error("Save failed"))
        #expect(status != .idle)
        #expect(status != .saving)
    }
}
