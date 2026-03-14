import Foundation
import SwiftUI

@Observable
final class CalendarViewModel {
    var scrollTarget: Date?

    private let calendar = Calendar.current
    private let expansionThreshold = 7  // days from edge to trigger expansion
    private let expansionAmount = 30    // days to add when expanding

    /// Cached date array — rebuilt only when startDate/endDate change
    private(set) var dates: [Date] = []
    private var startDate: Date
    private var endDate: Date

    init() {
        let today = DateFormatting.today
        self.startDate = Calendar.current.date(byAdding: .day, value: -90, to: today)!
        self.endDate = Calendar.current.date(byAdding: .day, value: 90, to: today)!
        self.dates = DateFormatting.dateRange(from: startDate, to: endDate)
    }

    var dateRangeStart: Date { startDate }
    var dateRangeEnd: Date { endDate }

    private func rebuildDates() {
        dates = DateFormatting.dateRange(from: startDate, to: endDate)
    }

    /// Check if we need to expand the date range when user approaches edges
    func expandIfNeeded(visibleDate: Date) {
        let daysFromStart = calendar.dateComponents([.day], from: startDate, to: visibleDate).day ?? 0
        let daysFromEnd = calendar.dateComponents([.day], from: visibleDate, to: endDate).day ?? 0

        var changed = false
        if daysFromStart < expansionThreshold {
            startDate = calendar.date(byAdding: .day, value: -expansionAmount, to: startDate)!
            changed = true
        }
        if daysFromEnd < expansionThreshold {
            endDate = calendar.date(byAdding: .day, value: expansionAmount, to: endDate)!
            changed = true
        }
        if changed { rebuildDates() }
    }

    /// Jump to a specific date, expanding range if needed
    func jumpTo(date: Date) {
        let normalized = DateFormatting.normalizeToDay(date)

        // Expand range to include the target date with padding
        var changed = false
        if normalized < startDate {
            startDate = calendar.date(byAdding: .day, value: -30, to: normalized)!
            changed = true
        }
        if normalized > endDate {
            endDate = calendar.date(byAdding: .day, value: 30, to: normalized)!
            changed = true
        }
        if changed { rebuildDates() }

        scrollTarget = normalized
    }

    func scrollToToday() {
        jumpTo(date: DateFormatting.today)
    }
}
