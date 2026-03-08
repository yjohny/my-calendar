import SwiftUI

struct HelpButtonOverlay: View {
    let onTap: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: onTap) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemGray), in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
                .padding(.trailing, 24)
                .padding(.bottom, 88)  // positioned above the today button
            }
        }
    }
}
