import Testing
import Foundation
@testable import TextCalKit

@Suite("Time Range Tests")
struct TimeRangeTests {
    @Test("Parses time range with shared AM/PM: 9:00-10:30 AM")
    func sharedAmPm() {
        let result = LineParser.parseEventLine("9:00-10:30 AM - Design review")
        #expect(result != nil)
        #expect(result?.timeComponents.hour == 9)
        #expect(result?.timeComponents.minute == 0)
        #expect(result?.endTimeComponents?.hour == 10)
        #expect(result?.endTimeComponents?.minute == 30)
        #expect(result?.title == "Design review")
    }

    @Test("Parses time range with separate AM/PM: 9:00 AM-10:30 AM")
    func separateAmPm() {
        let result = LineParser.parseEventLine("9:00 AM-10:30 AM - Meeting")
        #expect(result != nil)
        #expect(result?.timeComponents.hour == 9)
        #expect(result?.endTimeComponents?.hour == 10)
        #expect(result?.endTimeComponents?.minute == 30)
        #expect(result?.title == "Meeting")
    }

    @Test("Parses cross-period time range: 11:00 AM-1:00 PM")
    func crossPeriod() {
        let result = LineParser.parseEventLine("11:00 AM-1:00 PM - Lunch meeting")
        #expect(result != nil)
        #expect(result?.timeComponents.hour == 11)
        #expect(result?.endTimeComponents?.hour == 13)
        #expect(result?.title == "Lunch meeting")
    }

    @Test("Simple event still works (no end time)")
    func simpleEvent() {
        let result = LineParser.parseEventLine("9:00 AM - Standup")
        #expect(result != nil)
        #expect(result?.endTimeComponents == nil)
        #expect(result?.title == "Standup")
    }

    @Test("EntryLine includes end time for range events")
    func entryLineEndTime() {
        let result = LineParser.parse("9:00-10:30 AM - Review")
        guard case .event(let time, let endTime, let title, _, _, _) = result else {
            Issue.record("Expected event, got \(result)")
            return
        }
        #expect(time.hour == 9)
        #expect(endTime?.hour == 10)
        #expect(endTime?.minute == 30)
        #expect(title == "Review")
    }
}
