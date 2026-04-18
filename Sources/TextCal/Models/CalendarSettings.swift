import Foundation

/// Persists the user's default calendar choice via UserDefaults.
///
/// UserDefaults schema versioning:
/// The `settingsSchemaVersion` key records the shape of the settings this
/// build wrote. Future releases can read it on launch and migrate keys
/// (rename, reshape, or clean up) before the rest of the app reads them.
/// An unset value means "pre-versioned" and is treated as version 0.
///
/// Version history:
///   0 — unversioned (pre-1.0): defaultCalendarIdentifier, hiddenCalendarIdentifiers
///   1 — same keys, explicit version marker introduced
final class CalendarSettings {
    static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private let key = "defaultCalendarIdentifier"
    private let schemaVersionKey = "settingsSchemaVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateIfNeeded()
    }

    /// The schema version currently stored in UserDefaults.
    /// Returns 0 if no version marker has been written yet.
    var schemaVersion: Int {
        defaults.object(forKey: schemaVersionKey) as? Int ?? 0
    }

    /// Migrate UserDefaults forward to the current schema version.
    /// Called from init; safe to run repeatedly.
    private func migrateIfNeeded() {
        let current = schemaVersion
        if current >= Self.currentSchemaVersion { return }
        // Future per-version migrations go here, e.g.:
        //   if current < 2 { migrateV1toV2() }
        defaults.set(Self.currentSchemaVersion, forKey: schemaVersionKey)
    }

    /// The identifier of the user's chosen default calendar.
    /// When nil, falls back to the TextCal calendar.
    var defaultCalendarIdentifier: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    private let hiddenKey = "hiddenCalendarIdentifiers"
    private let iCloudSyncKey = "iCloudSyncEnabled"

    /// Whether per-day journal files and templates are stored in the app's
    /// iCloud Drive container instead of local Documents. Device-local; each
    /// device opts in independently. Changes take effect on next launch.
    var iCloudSyncEnabled: Bool {
        get { defaults.bool(forKey: iCloudSyncKey) }
        set { defaults.set(newValue, forKey: iCloudSyncKey) }
    }

    /// Set of calendar identifiers the user has hidden from display.
    var hiddenCalendarIdentifiers: Set<String> {
        get {
            let array = defaults.stringArray(forKey: hiddenKey) ?? []
            return Set(array)
        }
        set {
            defaults.set(Array(newValue), forKey: hiddenKey)
        }
    }

    /// Toggle visibility of a calendar. Returns the new hidden state.
    @discardableResult
    func toggleCalendarVisibility(_ identifier: String) -> Bool {
        var hidden = hiddenCalendarIdentifiers
        if hidden.contains(identifier) {
            hidden.remove(identifier)
            hiddenCalendarIdentifiers = hidden
            return false
        } else {
            hidden.insert(identifier)
            hiddenCalendarIdentifiers = hidden
            return true
        }
    }

    /// Check if a calendar is visible (not hidden).
    func isCalendarVisible(_ identifier: String) -> Bool {
        !hiddenCalendarIdentifiers.contains(identifier)
    }
}
