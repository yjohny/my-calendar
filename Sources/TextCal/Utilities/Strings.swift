import SwiftUI

/// Centralized user-facing strings for localization readiness.
enum Strings {
    // MARK: - Sync Status
    static let saving = LocalizedStringKey("Saving...")
    static let syncing = LocalizedStringKey("Syncing...")
    static let saveFailed = "Save failed"
    static let syncFailed = "Sync failed"

    // MARK: - Search
    static let searchPlaceholder = LocalizedStringKey("Search events and notes...")
    static let searchTitle = LocalizedStringKey("Search Your Calendar")
    static let searchDescription = LocalizedStringKey("Find events and notes across all days")
    static let searchNavTitle = LocalizedStringKey("Search")

    // MARK: - Editor
    static let editorPlaceholder = LocalizedStringKey("Type events like 9:00 AM - Meeting, or just write...")

    // MARK: - Common
    static let done = LocalizedStringKey("Done")
    static let cancel = LocalizedStringKey("Cancel")
    static let today = LocalizedStringKey("Today")
    static let settings = LocalizedStringKey("Settings")
    static let dismiss = LocalizedStringKey("Dismiss")

    // MARK: - Calendar Picker
    static let defaultCalendar = LocalizedStringKey("Default Calendar")

    // MARK: - Date Picker
    static let jumpToDate = LocalizedStringKey("Jump to Date")

    // MARK: - Toolbar
    static let todayButton = LocalizedStringKey("Today")
    static let searchButton = LocalizedStringKey("Search")
    static let calendarsButton = LocalizedStringKey("Calendars")
    static let helpButton = LocalizedStringKey("Help")

    // MARK: - Permission Banner
    static let calendarAccessDenied = LocalizedStringKey("Calendar access denied. Events won't sync.")
}
