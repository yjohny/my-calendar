import EventKit
import SwiftUI

/// A simple picker for choosing the default calendar for new events.
struct CalendarPickerView: View {
    let calendars: [EKCalendar]
    @Binding var selectedIdentifier: String?
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 12

    var body: some View {
        NavigationView {
            List {
                ForEach(calendars, id: \EKCalendar.calendarIdentifier) { (calendar: EKCalendar) in
                Button {
                    selectedIdentifier = calendar.calendarIdentifier
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: dotSize, height: dotSize)
                        Text(calendar.title)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        if calendar.calendarIdentifier == selectedIdentifier {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.medium)
                        }
                    }
                }
                .accessibilityLabel("\(calendar.title)\(calendar.calendarIdentifier == selectedIdentifier ? ", selected" : "")")
                }
            }
            .navigationTitle(Strings.defaultCalendar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text(Strings.done) }
                }
            }
        }
    }
}
