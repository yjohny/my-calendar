import SwiftUI

struct DaySectionView: View {
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DateHeaderView(date: date)
            DayTextEditor(date: date)
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }
}
