import EventKit
import Foundation

/// Handles search across day texts and EventKit events.
/// Extracted from CalendarStore to reduce its responsibility surface.
@MainActor
struct CalendarSearchService {
    /// Search all day texts for lines containing the query (case-insensitive).
    /// Searches most-recent dates first and stops early once maxResults is reached.
    static func searchDayTexts(
        query: String,
        dayTexts: [Date: String],
        maxResults: Int = 50
    ) -> [CalendarStore.SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lowered = query.lowercased()

        // Sort dates descending first, then search — enables early exit
        let sortedDates = dayTexts.keys.sorted(by: >)
        var results: [CalendarStore.SearchResult] = []

        for date in sortedDates {
            guard results.count < maxResults else { break }
            guard let text = dayTexts[date] else { continue }
            let lines = text.components(separatedBy: "\n")
            let matching = lines.filter { $0.lowercased().contains(lowered) }
            if !matching.isEmpty {
                results.append(CalendarStore.SearchResult(date: date, matchingLines: matching))
            }
        }

        return results
    }

    /// Search EventKit events across ±1 year for titles matching the query.
    /// Uses parsed event keys to check for duplicates instead of raw text contains().
    static func searchEventKitEvents(
        query: String,
        dayTexts: [Date: String],
        ekManager: EventKitManager,
        defaultCalId: String?,
        maxResults: Int = 50
    ) async -> [CalendarStore.EventKitSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let cal = Calendar.current
        let today = DateFormatting.today
        guard let start = cal.date(byAdding: .year, value: -1, to: today),
              let end = cal.date(byAdding: .year, value: 1, to: today) else { return [] }

        let events = await ekManager.searchEvents(query: query, from: start, to: end)

        // Group by day and filter out events already in user's text
        var resultsByDay: [Date: [String]] = [:]
        let lowered = query.lowercased()

        for event in events {
            let dayKey = DateFormatting.normalizeToDay(event.startDate)
            let userText = dayTexts[dayKey] ?? ""

            // Parse the user's text to find event keys (title + time), not raw text contains
            if !userText.isEmpty {
                let userKeys = parsedEventKeys(from: userText)
                let comps = cal.dateComponents([.hour, .minute], from: event.startDate)
                let eventKey = EventColorKey(
                    title: event.title ?? "",
                    hour: event.isAllDay ? nil : comps.hour,
                    minute: event.isAllDay ? nil : comps.minute,
                    isAllDay: event.isAllDay
                )
                if userKeys.contains(eventKey) {
                    continue
                }
            }

            let line = EventKitSync.textLine(from: event, defaultCalendarId: defaultCalId)
            if line.lowercased().contains(lowered) {
                resultsByDay[dayKey, default: []].append(line)
            }
        }

        var results = resultsByDay.map { CalendarStore.EventKitSearchResult(date: $0.key, matchingLines: $0.value) }
        results.sort { $0.date > $1.date }
        if results.count > maxResults {
            results = Array(results.prefix(maxResults))
        }
        return results
    }

    /// Parse event keys from user text for deduplication
    private static func parsedEventKeys(from text: String) -> Set<EventColorKey> {
        let lines = text.components(separatedBy: "\n")
        var keys = Set<EventColorKey>()
        for line in lines {
            let parsed = LineParser.parse(line)
            switch parsed {
            case .event(let time, _, let title, _, _, _):
                keys.insert(EventColorKey(
                    title: title,
                    hour: time.hour,
                    minute: time.minute,
                    isAllDay: false
                ))
            case .allDay(let title, _, _, _):
                keys.insert(EventColorKey(
                    title: title,
                    hour: nil,
                    minute: nil,
                    isAllDay: true
                ))
            default:
                break
            }
        }
        return keys
    }
}
