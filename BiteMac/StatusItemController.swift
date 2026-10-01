import AppKit

/// The ring in the menu bar. A click opens the panel; a right click, or a click with Control
/// held, shows the menu.
final class StatusItemController: NSObject {
    var onClick: () -> Void = {}
    var menu: () -> NSMenu = { NSMenu() }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var button: NSStatusBarButton? {
        item.button
    }

    /// Lit while the panel is open, as a menu's title is while its menu is.
    var isHighlighted = false {
        didSet { item.button?.highlight(isHighlighted) }
    }

    override init() {
        super.init()
        guard let button = item.button else { return }
        button.image = Self.ring
        button.setAccessibilityLabel("Bite")
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true else {
            onClick()
            // The highlight follows the panel, not the press, which AppKit clears once it's over.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                item.button?.highlight(isHighlighted)
            }
            return
        }
        // Set for the one click, the menu opens where a status item's menu does.
        item.menu = menu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// A ring, as a template the menu bar tints, the size and weight of Tot's beside it: 15 points
    /// across, its band 2.75, measured from a screenshot of the two side by side.
    private static let ring: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let diameter: CGFloat = 15
            let band: CGFloat = 2.75
            let circle = NSRect(x: (rect.width - diameter) / 2 + band / 2, y: (rect.height - diameter) / 2 + band / 2,
                                width: diameter - band, height: diameter - band)
            let path = NSBezierPath(ovalIn: circle)
            path.lineWidth = band
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
