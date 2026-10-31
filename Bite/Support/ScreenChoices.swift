import SwiftUI
import UIKit

/// What Settings asks of the screen while Bite is in front: that it stays on, and on a phone, that
/// Bite stays upright.
enum ScreenChoices {
    /// Whether iPhone folds, as iPhone Duo does, as its hinge has told (see `HingeReader`): there
    /// Bite stays upright on the outer display only, the inner one turning whatever an app allows.
    @MainActor static var folds = false

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

/// Hears from iPhone's hinge, where it has one, that it folds (see `ScreenChoices.folds`).
struct HingeReader: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        #if os(iOS)
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { _, update in
                if update.hinge != nil { ScreenChoices.folds = true }
            })
        }
        #endif
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
