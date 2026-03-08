import Foundation

/// Persists the user's default calendar choice via UserDefaults.
final class CalendarSettings {
    private let defaults: UserDefaults
    private let key = "defaultCalendarIdentifier"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The identifier of the user's chosen default calendar.
    /// When nil, falls back to the TextCal calendar.
    var defaultCalendarIdentifier: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
