import SwiftUI

struct DaySectionView: View {
    let date: Date
    var onHeaderTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeaderView(date: date, onTap: onHeaderTap)
            DayTextEditor(date: date)
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
    }
}
