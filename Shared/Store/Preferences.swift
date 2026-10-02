import Foundation

/// The choices in Settings, the same on the phone and the Mac. Each is kept in the defaults, and
/// a change is posted as `didChange`, which the pages and iCloud sync follow.
enum Preferences {
    static let didChange = Notification.Name("BitePreferencesDidChange")
    /// The tests' own in place of the app's, so they don't change the person's choices.
    static var defaults = UserDefaults.standard

    /// Whether the pages sync through iCloud. On unless turned off.
    static var syncsWithICloud: Bool {
        get { defaults.object(forKey: syncsWithICloudKey) as? Bool ?? true }
        set { set(newValue, forKey: syncsWithICloudKey) }
    }

    /// Whether misspelt words are underlined. Off unless turned on: notes go down fast and as
    /// typed, and the red lines only got in the way.
    static var checksSpelling: Bool {
        get { defaults.bool(forKey: checksSpellingKey) }
        set { set(newValue, forKey: checksSpellingKey) }
    }

    /// On the Mac, whether the panel is a pane of Liquid Glass rather than a page. Off unless
    /// turned on.
    static var panelIsGlass: Bool {
        get { defaults.bool(forKey: panelIsGlassKey) }
        set { set(newValue, forKey: panelIsGlassKey) }
    }

    /// On the phone, whether a checkbox clicks under the finger as it's ticked, and the dot bar
    /// ticks as a finger slides along it. On unless turned off.
    static var playsHaptics: Bool {
        get { defaults.object(forKey: playsHapticsKey) as? Bool ?? true }
        set { set(newValue, forKey: playsHapticsKey) }
    }

    private static let syncsWithICloudKey = "syncsWithICloud"
    private static let checksSpellingKey = "checksSpelling"
    private static let panelIsGlassKey = "panelIsGlass"
    private static let playsHapticsKey = "playsHaptics"

    private static func set(_ value: Bool, forKey key: String) {
        guard defaults.object(forKey: key) as? Bool != value else { return }
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// What Settings says before every page is reset (see `DotStore.resetAllPages`).
enum PageReset {
    static var message: String {
        let devices = Preferences.syncsWithICloud ? ", here and on your other devices" : ""
        return "All seven pages go back to how they were the first time Bite opened\(devices). This can't be undone."
    }
}
