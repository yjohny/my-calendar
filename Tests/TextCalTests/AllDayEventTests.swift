import Testing
import Foundation
@testable import TextCalKit

@Suite("All-Day Event Tests")
struct AllDayEventTests {
    @Test("Parses all-day event with * prefix")
    func basicAllDay() {
        let result = LineParser.parse("* Sarah's birthday")
        guard case .allDay(let title, let recurrence, _, _) = result else {
            Issue.record("Expected allDay, got \(result)")
            return
        }
        #expect(title == "Sarah's birthday")
        #expect(recurrence == nil)
    }

    @Test("Parses all-day event with recurrence")
    func allDayWithRecurrence() {
        let result = LineParser.parse("* Take vitamins (daily)")
        guard case .allDay(let title, let recurrence, _, _) = result else {
            Issue.record("Expected allDay, got \(result)")
            return
        }
        #expect(title == "Take vitamins")
        #expect(recurrence != nil)
        if case .daily = recurrence?.frequency {} else {
            Issue.record("Expected daily recurrence")
        }
    }

    @Test("All-day match returns correct parts")
    func allDayMatch() {
        let match = LineParser.parseAllDayLine("* Company holiday")
        #expect(match != nil)
        #expect(match?.title == "Company holiday")
        #expect(match?.recurrence == nil)
    }

    @Test("Regular text with * is not all-day (no space after)")
    func notAllDay() {
        let result = LineParser.parse("*bold text*")
        guard case .journal = result else {
            Issue.record("Expected journal, got \(result)")
            return
        }
    }

    @Test("All-day event with leading whitespace")
    func leadingWhitespace() {
        let result = LineParser.parse("  * Holiday")
        // Indented lines are event notes, not all-day
        guard case .eventNote = result else {
            Issue.record("Expected eventNote for indented line, got \(result)")
            return
        }
    }
}
