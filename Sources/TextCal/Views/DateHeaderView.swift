import SwiftUI

struct DateHeaderView: View {
    let date: Date
    var onTap: (() -> Void)?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        HStack {
            Text(DateFormatting.headerString(for: date))
                .font(.system(.headline, design: .monospaced))
                .fontWeight(isToday ? .bold : .medium)
                .foregroundStyle(isToday ? Color.accentColor : .primary)

            if isToday {
                Text("Today")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
