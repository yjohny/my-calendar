import SwiftUI

struct DateHeaderView: View {
    let date: Date
    var onTap: (() -> Void)?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(DateFormatting.headerString(for: date))
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(isToday ? .bold : .semibold)
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
                .textCase(.uppercase)

            if isToday {
                Text("  ·  Today")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                    .textCase(.uppercase)
            }

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 6)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
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
