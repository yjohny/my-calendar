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

    static let fromOtherApps = LocalizedStringKey("From Other Apps")

    // MARK: - Editor
    static let editorPlaceholder = LocalizedStringKey("Type events like 9:00 AM - Meeting, or just write...")

    // MARK: - Common
    static let done = LocalizedStringKey("Done")
    static let cancel = LocalizedStringKey("Cancel")
    static let today = LocalizedStringKey("Today")
    static let settings = LocalizedStringKey("Settings")
    static let dismiss = LocalizedStringKey("Dismiss")
    static let retry = LocalizedStringKey("Retry")

    // MARK: - Calendar Picker
    static let defaultCalendar = LocalizedStringKey("Default Calendar")

    // MARK: - Date Picker
    static let jumpToDate = LocalizedStringKey("Jump to Date")

    // MARK: - Toolbar
    static let todayButton = LocalizedStringKey("Today")
    static let searchButton = LocalizedStringKey("Search")
    static let calendarsButton = LocalizedStringKey("Calendars")
    static let helpButton = LocalizedStringKey("Help")

    // MARK: - Calendar Visibility
    static let calendarVisibility = LocalizedStringKey("Visibility")
    static let calendarVisibilityFooter = LocalizedStringKey("Hidden calendars won't appear in your daily view.")

    // MARK: - Unmatched Events
    static let eventsFromOtherCalendars = LocalizedStringKey("From other calendars")

    // MARK: - Move Event
    static let moveToTomorrow = LocalizedStringKey("Move to Tomorrow")
    static let moveToDate = LocalizedStringKey("Move to Date...")

    // MARK: - Week View
    static let weekView = LocalizedStringKey("Week")

    // MARK: - Events Only Filter
    static let eventsOnlyLabel = LocalizedStringKey("Events Only")
    static let showAllContent = LocalizedStringKey("Show All")

    // MARK: - Templates
    static let templates = LocalizedStringKey("Templates")
    static let noTemplates = LocalizedStringKey("No Templates")
    static let noTemplatesDescription = LocalizedStringKey("Save frequently used events as templates for quick insertion.")
    static let templateName = LocalizedStringKey("Name")
    static let templateContent = LocalizedStringKey("Content")
    static let templateContentFooter = LocalizedStringKey("Use event syntax like \"9:00 AM - Meeting\" or plain text.")
    static let newTemplate = LocalizedStringKey("New Template")
    static let editTemplate = LocalizedStringKey("Edit Template")

    // MARK: - Permission Banner
    static let calendarAccessDenied = LocalizedStringKey("Calendar access denied. Events won't sync.")

    // MARK: - Data Export
    static let dataSection = LocalizedStringKey("Data")
    static let exportAllData = LocalizedStringKey("Export All Data")
    static let exportFooter = LocalizedStringKey("Export all your journal text as a single document. Share it to Files, Mail, or another app to keep a backup.")
    static let preparingExport = LocalizedStringKey("Preparing export...")

    // MARK: - iCloud Sync
    static let syncSection = LocalizedStringKey("Sync")
    static let iCloudSyncToggle = LocalizedStringKey("Sync via iCloud")
    static let iCloudSyncFooter = LocalizedStringKey("When on, your journal text and templates are stored in iCloud Drive so they appear on all your devices signed into the same Apple ID. Events already sync via your Calendar accounts. Relaunch TextCal after changing this setting.")
    static let iCloudUnavailableTitle = LocalizedStringKey("iCloud Not Available")
    static let iCloudUnavailableMessage = LocalizedStringKey("Sign in to iCloud and enable iCloud Drive in Settings, then try again.")
    static let relaunchRequiredTitle = LocalizedStringKey("Relaunch to Apply")
    static let relaunchRequiredMessage = LocalizedStringKey("Quit and reopen TextCal to start using the new storage location. Your existing journal will be copied over automatically.")
    static let ok = LocalizedStringKey("OK")
}
