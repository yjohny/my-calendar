import SwiftUI

struct CalendarButtonOverlay: View {
    let onTap: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onTap) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray6), in: Circle())
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 108)  // positioned above the help button
            }
        }
    }
}
