import SwiftUI

struct DaySectionView: View {
    let date: Date
    var onHeaderTap: (() -> Void)?
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeaderView(date: date, onTap: onHeaderTap)
            DayTextEditor(date: date)
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
        .onAppear {
            prefetchNearbyDates()
        }
    }

    /// Prefetch EventKit data for adjacent days so they're ready when the user scrolls
    private func prefetchNearbyDates() {
        let calendar = Calendar.current
        Task {
            for offset in [-1, 1, 2] {
                if let nearby = calendar.date(byAdding: .day, value: offset, to: date) {
                    let key = DateFormatting.normalizeToDay(nearby)
                    // Only prefetch if we haven't loaded color data for this date yet
                    if store.eventColorMap[key] == nil {
                        await store.refreshEvents(for: key)
                    }
                }
            }
        }
    }
}
