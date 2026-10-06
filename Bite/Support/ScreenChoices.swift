import UIKit

/// What Settings asks of the screen while Bite is in front: that it stays on, and on a phone, that
/// Bite stays upright.
enum ScreenChoices {
    /// The ways Bite turns: upright only, on a phone when Settings says so, else as its Info.plist
    /// lists for the device.
    static var orientations: UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return Preferences.locksPortrait ? .portrait : .allButUpsideDown
    }

    /// Follows Settings: the screen stays on or not, and Bite, lying on its side when it may no
    /// longer, turns upright, or turns with the phone again when it may.
    static func apply() {
        UIApplication.shared.isIdleTimerDisabled = Preferences.keepsScreenOn
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if orientations == .portrait, scene.effectiveGeometry.interfaceOrientation != .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
    }
}
