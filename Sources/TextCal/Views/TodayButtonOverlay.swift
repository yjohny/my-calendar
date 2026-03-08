import SwiftUI

struct TodayButtonOverlay: View {
    let onTap: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onTap) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 20)
            }
        }
    }
}
