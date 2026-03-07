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
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
