import OSLog
import WatchKit

/// Lets Bite sync on the watch while it's off screen, at times the system picks: every so often,
/// asked for no more than every 15 minutes, which the system grants only to apps on the watch
/// face. iCloud's pushes wake it too (see `WatchAppDelegate`).
enum BackgroundSync {
    static let refreshID = "com.chenyeni.bite.refresh"

    /// As Bite leaves the screen, and after each run: the next chance. Asked again, the system
    /// replaces what was asked before.
    static func schedule() {
        let log = PageSync.log
        // The name picks the scene's handler for it (see `BiteWatchApp`).
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: .now + 15 * 60,
                                                         userInfo: refreshID as NSString) { @Sendable error in
            if let error {
                log.error("Couldn't ask for a background refresh: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The system woke Bite for the refresh it asked for: other devices' changes come down, and
    /// what's waiting goes up, in the few seconds it's given.
    static func run() async {
        schedule()
        await PageSync.shared?.syncInBackground("refresh")
    }
}
