import Testing
@testable import TextCalKit

@Suite("LineParser Tests")
struct LineParserTests {
    @Test("Parses simple AM time event")
    func simpleAMEvent() {
        let result = LineParser.parse("9:00 AM - Team standup")
        guard case .event(let time, let title) = result else {
            Issue.record("Expected event, got \(result)")
            return
        }
        #expect(time.hour == 9)
        #expect(time.minute == 0)
        #expect(title == "Team standup")
    }

    @Test("Parses PM time event")
    func pmEvent() {
        let result = LineParser.parse("2:00 PM - Call with client")
        guard case .event(let time, let title) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 14)
        #expect(time.minute == 0)
        #expect(title == "Call with client")
    }

    @Test("Parses 24-hour time event")
    func twentyFourHourEvent() {
        let result = LineParser.parse("14:30 - Meeting")
        guard case .event(let time, let title) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 14)
        #expect(time.minute == 30)
        #expect(title == "Meeting")
    }

    @Test("Parses time without minutes")
    func timeWithoutMinutes() {
        let result = LineParser.parse("2 PM - Lunch")
        guard case .event(let time, let title) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 14)
        #expect(time.minute == 0)
        #expect(title == "Lunch")
    }

    @Test("Parses lowercase am/pm")
    func lowercaseAmPm() {
        let result = LineParser.parse("10:30 am - Brunch")
        guard case .event(let time, let title) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 10)
        #expect(time.minute == 30)
        #expect(title == "Brunch")
    }

    @Test("Parses 12 PM correctly")
    func twelvePM() {
        let result = LineParser.parse("12:00 PM - Noon meeting")
        guard case .event(let time, _) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 12)
    }

    @Test("Parses 12 AM correctly")
    func twelveAM() {
        let result = LineParser.parse("12:00 AM - Midnight snack")
        guard case .event(let time, _) = result else {
            Issue.record("Expected event")
            return
        }
        #expect(time.hour == 0)
    }

    @Test("Recognizes journal text")
    func journalText() {
        let result = LineParser.parse("Had a productive morning.")
        guard case .journal(let text) = result else {
            Issue.record("Expected journal")
            return
        }
        #expect(text == "Had a productive morning.")
    }

    @Test("Recognizes blank lines")
    func blankLine() {
        #expect(LineParser.parse("") == .blank)
        #expect(LineParser.parse("   ") == .blank)
    }

    @Test("Recognizes indented note lines")
    func indentedNote() {
        let result = LineParser.parse("  Remember to bring insurance card")
        guard case .eventNote(let text) = result else {
            Issue.record("Expected eventNote")
            return
        }
        #expect(text == "Remember to bring insurance card")
    }

    @Test("Event line match returns correct parts")
    func eventLineMatch() {
        let match = LineParser.parseEventLine("9:00 AM - Team standup")
        #expect(match != nil)
        #expect(match?.timeText == "9:00 AM")
        #expect(match?.title == "Team standup")
    }

    @Test("Non-event line returns nil match")
    func nonEventLineMatch() {
        #expect(LineParser.parseEventLine("Just a regular note") == nil)
        #expect(LineParser.parseEventLine("") == nil)
    }

    @Test("Parses multiple lines")
    func parseAll() {
        let text = """
9:00 AM - Standup
Had coffee.

2:00 PM - Meeting
"""
        let lines = LineParser.parseAll(text)
        #expect(lines.count == 4)
    }
}
