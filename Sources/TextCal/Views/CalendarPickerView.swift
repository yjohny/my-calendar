import EventKit
import SwiftUI

/// A picker for choosing the default calendar and toggling calendar visibility.
struct CalendarPickerView: View {
    let calendars: [EKCalendar]
    @Binding var selectedIdentifier: String?
    let calendarSettings: CalendarSettings?
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 12
    @State private var hiddenIds: Set<String> = []

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(calendars, id: \EKCalendar.calendarIdentifier) { (calendar: EKCalendar) in
                        Button {
                            selectedIdentifier = calendar.calendarIdentifier
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
                } header: {
                    Text(Strings.defaultCalendar)
                }

                Section {
                    ForEach(calendars, id: \EKCalendar.calendarIdentifier) { (calendar: EKCalendar) in
                        Button {
                            let isNowHidden = calendarSettings?.toggleCalendarVisibility(calendar.calendarIdentifier) ?? false
                            if isNowHidden {
                                hiddenIds.insert(calendar.calendarIdentifier)
                            } else {
                                hiddenIds.remove(calendar.calendarIdentifier)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: dotSize, height: dotSize)
                                    .opacity(hiddenIds.contains(calendar.calendarIdentifier) ? 0.3 : 1.0)
                                Text(calendar.title)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(hiddenIds.contains(calendar.calendarIdentifier) ? .secondary : .primary)
                                Spacer()
                                Image(systemName: hiddenIds.contains(calendar.calendarIdentifier) ? "eye.slash" : "eye")
                                    .foregroundStyle(hiddenIds.contains(calendar.calendarIdentifier) ? .secondary : Color.accentColor)
                                    .font(.body)
                            }
                        }
                        .accessibilityLabel("\(calendar.title), \(hiddenIds.contains(calendar.calendarIdentifier) ? "hidden" : "visible")")
                        .accessibilityHint("Double tap to toggle visibility")
                    }
                } header: {
                    Text(Strings.calendarVisibility)
                } footer: {
                    Text(Strings.calendarVisibilityFooter)
                }
            }
            .navigationTitle(Strings.calendarsButton)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text(Strings.done) }
                }
            }
            .onAppear {
                hiddenIds = calendarSettings?.hiddenCalendarIdentifiers ?? []
            }
        }
    }
}
