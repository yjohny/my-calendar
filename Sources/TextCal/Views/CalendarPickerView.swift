import EventKit
import SwiftUI

/// A simple picker for choosing the default calendar for new events.
struct CalendarPickerView: View {
    let calendars: [EKCalendar]
    @Binding var selectedIdentifier: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                Button {
                    selectedIdentifier = calendar.calendarIdentifier
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: 12, height: 12)
                        Text(calendar.title)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        if calendar.calendarIdentifier == selectedIdentifier {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                                .fontWeight(.medium)
                        }
                    }
                }
                }
            }
            .navigationTitle("Default Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
