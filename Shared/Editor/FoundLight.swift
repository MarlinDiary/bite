import Foundation
import QuartzCore

/// The light on the text a page was opened at, from a search outside Bite: a layer under the text
/// in the page's colour, as the selection lights text, drawn by the text view. It shows at once,
/// stays a moment once Bite is on screen, and goes by itself, about a second in all: a flash that
/// shows where to look. Staying until the page was touched was wrong, the user said, and 1.5 s
/// held with a 0.8 s fade still too long (2026-10-06). Touched, scrolled or a key pressed before
/// then, it goes quickly; with the text changed under it, or off screen, at once.
final class FoundLight {
    enum Fade {
        /// Out of the way as the page is used.
        case quick
        /// By itself, once it has been seen: calmly, nothing having asked for it.
        case slow
        /// Where a fade would show it somewhere it no longer belongs, as over text that moved, or
        /// where it isn't seen.
        case atOnce
    }

    static let quickFade: CFTimeInterval = 0.25
    static let slowFade: CFTimeInterval = 0.4

    let layer = CAShapeLayer()
    /// The text lit, until its light starts to go.
    private(set) var range: NSRange?
    /// How long it stays lit once Bite is on screen.
    var hold: TimeInterval = 0.6
    private var countdown: DispatchWorkItem?

    /// Lights `range` at once. It goes by itself once `countDown` is called.
    func show(_ range: NSRange) {
        countdown?.cancel()
        countdown = nil
        self.range = range
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.opacity = 1
        CATransaction.commit()
    }

    /// Starts the moment it stays lit, as Bite is on screen. Started already, it carries on.
    func countDown() {
        guard range != nil, countdown == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hide(.slow)
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    func hide(_ fade: Fade) {
        countdown?.cancel()
        countdown = nil
        switch fade {
        case .quick, .slow:
            guard range != nil else { return }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1
            animation.toValue = 0
            animation.duration = fade == .quick ? Self.quickFade : Self.slowFade
            animation.timingFunction = CAMediaTimingFunction(name: fade == .quick ? .easeOut : .easeInEaseOut)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.add(animation, forKey: "opacity")
            layer.opacity = 0
            CATransaction.commit()
        case .atOnce:
            // Fading already, it goes too.
            guard range != nil || layer.animation(forKey: "opacity") != nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAllAnimations()
            layer.opacity = 0
            CATransaction.commit()
        }
        range = nil
    }

    #if DEBUG
    /// How long the light is fading out over, while it does. For tests.
    var fadeForTesting: CFTimeInterval? {
        layer.animation(forKey: "opacity")?.duration
    }
    #endif
}
