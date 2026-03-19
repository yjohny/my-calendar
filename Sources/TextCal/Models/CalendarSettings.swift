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

    private let hiddenKey = "hiddenCalendarIdentifiers"

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
