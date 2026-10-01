import AppKit

/// A row of Bite's own menus, drawn by Bite so that its highlight takes the page's colour:
/// AppKit's takes the system's accent, and can't be told otherwise. It's laid out as AppKit lays
/// out a row with a picture and keys, measured on macOS 27, and keeps AppKit's separators.
final class MenuRow: NSView {
    private let title: String
    private let symbol: String
    /// The key shown after ⌘, as AppKit shows it: a letter as a capital.
    private let key: String
    private let tint: NSColor

    static let height: CGFloat = 24
    /// The highlight is inset this far from the menu's sides, with these corners.
    private static let inset: CGFloat = 5
    private static let cornerRadius: CGFloat = 8
    private static let imageCenter: CGFloat = 22.25
    private static let titleStart: CGFloat = 36
    /// The keys are in two columns, measured from the right: ⌘ starting here, and the key
    /// centred on the second.
    private static let modifierStart: CGFloat = 41
    private static let keyCenter: CGFloat = 22.25
    /// Between the longest title and the keys, as AppKit leaves.
    private static let keysGap: CGFloat = 21.5
    private static let font = NSFont.menuFont(ofSize: 0)

    /// The item for `title`, sending `action` to `target`, with `tint` as its highlight.
    static func item(_ title: String, symbol: String, key: String = "", action: Selector, target: AnyObject?,
                     tint: NSColor, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.isEnabled = isEnabled
        item.view = MenuRow(title: title, symbol: symbol, key: key, tint: tint)
        return item
    }

    private init(title: String, symbol: String, key: String, tint: NSColor) {
        self.title = title
        self.symbol = symbol
        self.key = key.uppercased()
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(title: title), height: Self.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Wide enough for the title and the keys. Each of Bite's menus has keys on some row, and AppKit
    /// then leaves room for them on every row. The menu takes its widest row, and the others
    /// stretch to it.
    private static func width(title: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return (titleStart + titleWidth + keysGap + modifierStart).rounded(.up)
    }

    override var isFlipped: Bool { true }

    private var isLit: Bool {
        guard let item = enclosingMenuItem else { return false }
        return item.isHighlighted && item.isEnabled
    }

    override func draw(_ dirtyRect: NSRect) {
        let isEnabled = enclosingMenuItem?.isEnabled ?? true
        if isLit {
            tint.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: Self.inset, dy: 0), xRadius: Self.cornerRadius,
                         yRadius: Self.cornerRadius).fill()
        }
        let ink: NSColor = isLit ? .selectedMenuItemTextColor : isEnabled ? .labelColor : .tertiaryLabelColor
        let keyInk: NSColor = isLit ? .selectedMenuItemTextColor : isEnabled ? .tertiaryLabelColor : .quaternaryLabelColor
        drawImage(in: ink)
        let font = Self.font
        // The capitals centred on the row, as AppKit sets a row's title.
        let top = ((bounds.height - font.capHeight) / 2 + font.capHeight - font.ascender).rounded()
        (title as NSString).draw(at: NSPoint(x: Self.titleStart, y: top), withAttributes: [.font: font, .foregroundColor: ink])
        guard !key.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: keyInk]
        ("⌘" as NSString).draw(at: NSPoint(x: bounds.maxX - Self.modifierStart, y: top), withAttributes: attributes)
        let keyWidth = (key as NSString).size(withAttributes: attributes).width
        (key as NSString).draw(at: NSPoint(x: bounds.maxX - Self.keyCenter - keyWidth / 2, y: top), withAttributes: attributes)
    }

    private func drawImage(in ink: NSColor) {
        // The colour's own alpha goes in as the picture's: given to the symbol, it went in twice
        // and the picture came out paler than AppKit's.
        let resolved = ink.usingColorSpace(.sRGB) ?? ink
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold, scale: .small)
            .applying(NSImage.SymbolConfiguration(paletteColors: [resolved.withAlphaComponent(1)]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let frame = NSRect(x: Self.imageCenter - size.width / 2, y: (bounds.height - size.height) / 2,
                           width: size.width, height: size.height)
        // Upright in the row's top-down coordinates, which this way of drawing ignores unless told.
        image.draw(in: backingAlignedRect(frame, options: .alignAllEdgesNearest), from: .zero, operation: .sourceOver,
                   fraction: resolved.alphaComponent, respectFlipped: true, hints: nil)
    }

    /// AppKit sends a row's action only when it draws the row itself: a click on this one closes
    /// the menu and sends it, as AppKit would.
    override func mouseUp(with event: NSEvent) {
        choose()
    }

    /// As VoiceOver presses a row.
    override func accessibilityPerformPress() -> Bool {
        choose()
        return true
    }

    private func choose() {
        guard let item = enclosingMenuItem, item.isEnabled, let menu = item.menu else { return }
        Self.keyboard.choose(item, in: menu)
    }
}

extension MenuRow {
    /// AppKit leaves a row with a view of its own to the view: a click reaches it (see `mouseUp`),
    /// but Return, Enter or Space on the highlighted row only closes the menu, without a word to
    /// anyone. Set as the menu's delegate, this sends a clicked row's action once the menu has
    /// gone, and chooses the highlighted row when the key comes back up, which it does once the
    /// menu has gone. Anything else first, such as typing on, and it isn't.
    static let keyboard = Keyboard()

    final class Keyboard: NSObject, NSMenuDelegate {
        private weak var highlighted: NSMenuItem?
        private var chosen: NSMenuItem?
        private var monitor: Any?
        /// Which wait the timer ends, so it doesn't end one for a menu opened since.
        private var waits = 0
        private static let chooseKeys: Set<UInt16> = [36, 76, 49]

        /// Chosen with a click: the menu closes, and the row's action is sent once it has gone, as
        /// AppKit sends its own rows'. Sent at once, it opened Settings with the menu still up,
        /// which only went once the window was ready.
        func choose(_ item: NSMenuItem, in menu: NSMenu) {
            highlighted = nil
            chosen = item
            menu.cancelTracking()
        }

        func menuWillOpen(_ menu: NSMenu) {
            chosen = nil
        }

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            // Closing, since macOS 26.4, a menu is first told nothing is highlighted. While it's
            // open, only the pointer leaving the rows takes the highlight away.
            if item == nil, let event = NSApp.currentEvent, !Self.isPointer(event) { return }
            highlighted = item
        }

        func menuDidClose(_ menu: NSMenu) {
            stopWaiting()
            if let item = chosen, item.menu === menu {
                chosen = nil
                highlighted = nil
                // Out of the menu's own tracking, which has taken it off the screen by then.
                perform(#selector(sendChosen(_:)), with: item, afterDelay: 0, inModes: [.default])
                return
            }
            let item = highlighted
            highlighted = nil
            guard let item, item.isEnabled, item.view is MenuRow else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.stopWaiting()
                if event.type == .keyUp, Self.chooseKeys.contains(event.keyCode) {
                    Self.send(item)
                }
                return event
            }
            waits += 1
            let wait = waits
            // A key held down that long wasn't a press.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.waits == wait { self?.stopWaiting() }
            }
        }

        @objc private func sendChosen(_ item: NSMenuItem) {
            Self.send(item)
        }

        /// Straight to the row's target: Bite's menus are made for each showing, and by the time a
        /// row's action goes, its menu is gone. Sent through the menu, Settings never opened.
        private static func send(_ item: NSMenuItem) {
            guard let action = item.action else { return }
            NSApp.sendAction(action, to: item.target, from: item)
        }

        private func stopWaiting() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private static func isPointer(_ event: NSEvent) -> Bool {
            [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel].contains(event.type)
        }
    }
}
