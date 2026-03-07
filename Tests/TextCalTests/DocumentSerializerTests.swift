import Testing
import Foundation
@testable import TextCalKit

@Suite("DocumentSerializer Tests")
struct DocumentSerializerTests {
    @Test("Serialize empty dictionary produces empty string")
    func serializeEmpty() {
        let result = DocumentSerializer.serialize(days: [:])
        #expect(result == "")
    }

    @Test("Serialize single day")
    func serializeSingleDay() {
        let date = makeDate(year: 2026, month: 3, day: 9) // Monday
        let days: [Date: DayEntry] = [
            date: DayEntry(id: date, rawText: "9:00 AM - Team standup\nHad a good day.")
        ]
        let result = DocumentSerializer.serialize(days: days)
        #expect(result.contains("# Monday, March 9, 2026"))
        #expect(result.contains("9:00 AM - Team standup"))
        #expect(result.contains("Had a good day."))
    }

    @Test("Serialize multiple days in chronological order")
    func serializeMultipleDays() {
        let date1 = makeDate(year: 2026, month: 3, day: 9)
        let date2 = makeDate(year: 2026, month: 3, day: 10)
        let days: [Date: DayEntry] = [
            date2: DayEntry(id: date2, rawText: "Working from home."),
            date1: DayEntry(id: date1, rawText: "Office day.")
        ]
        let result = DocumentSerializer.serialize(days: days)
        let range1 = result.range(of: "March 9")!
        let range2 = result.range(of: "March 10")!
        #expect(range1.lowerBound < range2.lowerBound)
    }

    @Test("Deserialize empty string produces empty array")
    func deserializeEmpty() {
        let result = DocumentSerializer.deserialize("")
        #expect(result.isEmpty)
    }

    @Test("Deserialize single day")
    func deserializeSingleDay() {
        let input = """
# Monday, March 9, 2026

9:00 AM - Team standup
Had a good day.
"""
        let result = DocumentSerializer.deserialize(input)
        #expect(result.count == 1)
        #expect(result[0].rawText.contains("9:00 AM - Team standup"))
        #expect(result[0].rawText.contains("Had a good day."))
    }

    @Test("Deserialize multiple days")
    func deserializeMultipleDays() {
        let input = """
# Monday, March 9, 2026

Office day.

# Tuesday, March 10, 2026

Working from home.
"""
        let result = DocumentSerializer.deserialize(input)
        #expect(result.count == 2)
    }

    @Test("Round-trip serialization preserves content")
    func roundTrip() {
        let date1 = makeDate(year: 2026, month: 3, day: 9)
        let date2 = makeDate(year: 2026, month: 3, day: 10)
        let original: [Date: DayEntry] = [
            date1: DayEntry(id: date1, rawText: "9:00 AM - Standup\nGood morning."),
            date2: DayEntry(id: date2, rawText: "2:00 PM - Call\nRemote day.")
        ]

        let serialized = DocumentSerializer.serialize(days: original)
        let deserialized = DocumentSerializer.deserialize(serialized)

        #expect(deserialized.count == 2)

        let day1 = deserialized.first { Calendar.current.isDate($0.date, inSameDayAs: date1) }
        #expect(day1 != nil)
        #expect(day1?.rawText.contains("9:00 AM - Standup") == true)
        #expect(day1?.rawText.contains("Good morning.") == true)
    }

    @Test("Skips empty days during serialization")
    func skipsEmptyDays() {
        let date = makeDate(year: 2026, month: 3, day: 9)
        let days: [Date: DayEntry] = [
            date: DayEntry(id: date, rawText: "  \n  ")
        ]
        let result = DocumentSerializer.serialize(days: days)
        #expect(result == "")
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
