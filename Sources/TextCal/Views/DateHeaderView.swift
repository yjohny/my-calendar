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
                .font(.system(.headline, design: .rounded))
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

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DateFormatting.headerString(for: date) + (isToday ? ", Today" : ""))
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
        .accessibilityHint(onTap != nil ? "Opens date picker" : "")
    }
}
