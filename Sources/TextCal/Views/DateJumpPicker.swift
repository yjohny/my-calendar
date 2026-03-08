import SwiftUI

/// A compact date picker presented as a sheet for jumping to a specific date
struct DateJumpPicker: View {
    @Binding var selectedDate: Date
    let onJump: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Jump to date",
                    selection: $selectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)

                Button {
                    onJump(selectedDate)
                    dismiss()
                } label: {
                    Text("Go to \(formattedDate)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Jump to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Today") {
                        selectedDate = DateFormatting.today
                        onJump(selectedDate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var formattedDate: String {
        DateFormatting.headerString(for: selectedDate)
    }
}
