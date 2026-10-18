#if DIRECT_DISTRIBUTION
import AppKit
import Sparkle

/// Bite downloaded from GitHub keeps itself up to date with Sparkle: it looks now and then at the
/// list of versions on Bite's website, each signed with the developer's key, and offers a newer
/// one in Sparkle's own window. The App Store updates the App Store's Bite, which is built without
/// any of this (see `BITE_DIRECT` in the project).
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    private lazy var controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                                userDriverDelegate: self)

    /// From launch on, as Sparkle schedules it.
    func start() {
        _ = controller
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    // Bite lives in the menu bar, with no window of its own to come forward: a newer version
    // found on a scheduled look is shown at once.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                        andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}
#endif
