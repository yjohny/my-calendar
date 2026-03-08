import Foundation
import SwiftUI

@Observable
final class CalendarViewModel {
    var startDate: Date
    var endDate: Date
    var scrollTarget: Date?

    private let calendar = Calendar.current
    private let expansionThreshold = 7  // days from edge to trigger expansion
    private let expansionAmount = 30    // days to add when expanding

    var dates: [Date] {
        DateFormatting.dateRange(from: startDate, to: endDate)
    }

    init() {
        let today = DateFormatting.today
        self.startDate = Calendar.current.date(byAdding: .day, value: -90, to: today)!
        self.endDate = Calendar.current.date(byAdding: .day, value: 90, to: today)!
    }

    /// Check if we need to expand the date range when user approaches edges
    func expandIfNeeded(visibleDate: Date) {
        let daysFromStart = calendar.dateComponents([.day], from: startDate, to: visibleDate).day ?? 0
        let daysFromEnd = calendar.dateComponents([.day], from: visibleDate, to: endDate).day ?? 0

        if daysFromStart < expansionThreshold {
            startDate = calendar.date(byAdding: .day, value: -expansionAmount, to: startDate)!
        }
        if daysFromEnd < expansionThreshold {
            endDate = calendar.date(byAdding: .day, value: expansionAmount, to: endDate)!
        }
    }

    /// Jump to a specific date, expanding range if needed
    func jumpTo(date: Date) {
        let normalized = DateFormatting.normalizeToDay(date)

        // Expand range to include the target date with padding
        if normalized < startDate {
            startDate = calendar.date(byAdding: .day, value: -30, to: normalized)!
        }
        if normalized > endDate {
            endDate = calendar.date(byAdding: .day, value: 30, to: normalized)!
        }

        scrollTarget = normalized
    }

    func scrollToToday() {
        jumpTo(date: DateFormatting.today)
    }
}
