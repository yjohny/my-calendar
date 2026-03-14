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

    /// Prefetch EventKit data for nearby days in a single batch query
    private func prefetchNearbyDates() {
        let calendar = Calendar.current
        guard let rangeStart = calendar.date(byAdding: .day, value: -1, to: date),
              let rangeEnd = calendar.date(byAdding: .day, value: 2, to: date) else { return }

        // Skip if all dates in range are already loaded
        let startKey = DateFormatting.normalizeToDay(rangeStart)
        let endKey = DateFormatting.normalizeToDay(rangeEnd)
        if store.eventColorMap[startKey] != nil && store.eventColorMap[endKey] != nil {
            return
        }

        Task {
            await store.refreshEventsInRange(from: rangeStart, to: rangeEnd)
        }
    }
}
