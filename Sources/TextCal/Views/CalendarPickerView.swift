import EventKit
import SwiftUI

/// A picker for choosing the default calendar and toggling calendar visibility.
struct CalendarPickerView: View {
    let calendars: [EKCalendar]
    @Binding var selectedIdentifier: String?
    let calendarSettings: CalendarSettings?
    /// Optional store used for data export. When nil, the export section is hidden.
    var store: CalendarStore?
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 12
    @State private var hiddenIds: Set<String> = []
    @State private var exportedText: String?
    @State private var isExporting = false
    @State private var iCloudSyncEnabled = false
    @State private var showICloudUnavailableAlert = false
    @State private var showRelaunchAlert = false

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

                Section {
                    Toggle(isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in setICloudSync(newValue) }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "icloud")
                                .foregroundStyle(Color.accentColor)
                            Text(Strings.iCloudSyncToggle)
                                .font(.system(.body, design: .rounded))
                        }
                    }
                    .accessibilityHint("Stores journal text and templates in iCloud Drive so they sync across your devices")
                } header: {
                    Text(Strings.syncSection)
                } footer: {
                    Text(Strings.iCloudSyncFooter)
                }

                if let store {
                    Section {
                        if let exportedText {
                            ShareLink(
                                item: exportedText,
                                preview: SharePreview("TextCal Export")
                            ) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(Strings.exportAllData)
                                        .font(.system(.body, design: .rounded))
                                }
                            }
                        } else {
                            Button {
                                isExporting = true
                                Task {
                                    let text = await store.exportAllDataAsText()
                                    await MainActor.run {
                                        exportedText = text
                                        isExporting = false
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(isExporting ? Strings.preparingExport : Strings.exportAllData)
                                        .font(.system(.body, design: .rounded))
                                    if isExporting {
                                        Spacer()
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isExporting)
                            .accessibilityLabel(Strings.exportAllData)
                            .accessibilityHint("Creates a single document with all your journal text for backup")
                        }
                    } header: {
                        Text(Strings.dataSection)
                    } footer: {
                        Text(Strings.exportFooter)
                    }
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
                iCloudSyncEnabled = calendarSettings?.iCloudSyncEnabled ?? false
            }
            .alert(Strings.iCloudUnavailableTitle, isPresented: $showICloudUnavailableAlert) {
                Button(Strings.ok, role: .cancel) {}
            } message: {
                Text(Strings.iCloudUnavailableMessage)
            }
            .alert(Strings.relaunchRequiredTitle, isPresented: $showRelaunchAlert) {
                Button(Strings.ok, role: .cancel) {}
            } message: {
                Text(Strings.relaunchRequiredMessage)
            }
        }
    }

    /// Persist the iCloud sync toggle. When turning on, verify the ubiquity
    /// container is reachable — if not, revert the toggle and tell the user.
    /// A successful flip prompts the user to relaunch the app.
    private func setICloudSync(_ newValue: Bool) {
        guard let calendarSettings else { return }
        if newValue {
            Task { @MainActor in
                let available = await Task.detached(priority: .userInitiated) {
                    FileStore.cloudBaseURL() != nil
                }.value
                if available {
                    calendarSettings.iCloudSyncEnabled = true
                    iCloudSyncEnabled = true
                    showRelaunchAlert = true
                } else {
                    iCloudSyncEnabled = false
                    showICloudUnavailableAlert = true
                }
            }
        } else {
            calendarSettings.iCloudSyncEnabled = false
            iCloudSyncEnabled = false
            showRelaunchAlert = true
        }
    }
}
