import AppKit
import SwiftUI
import BiteKit

/// The panel the ring in the menu bar opens, just below it: the dot bar over the page of the
/// dot picked. It takes typing even while the system won't make Bite the active app, and goes
/// away as soon as anything else is clicked. A swipe to another Space takes it along. Dragged by
/// its top, it comes away from the ring and stays where it's put until it's closed.
final class PanelController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let store: DotStore
    weak var statusItem: StatusItemController?

    private let panel: BitePanel
    /// What the panel shows: the pages, the dot bar, a link's card and pill.
    private let pages: PanelPages
    var controllers: [EditorController] { pages.controllers }
    /// The page mostly on screen while a swipe moves between two, which the dot bar follows.
    var onScreen: PageOnScreen { pages.onScreen }
    let placement = PanelPlacement()
    /// Set while the panel is put below the ring, which isn't a drag taking it away.
    private var isPositioning = false
    private var background: PageBackgroundView { pages.background }
    private var topBar: NSView? { pages.topBar }
    private var linkCard: LinkCard { pages.linkCard }
    private var linkBubble: LinkBubble { pages.linkBubble }
    private var linkShield: LinkShield { pages.linkShield }
    /// Kept open, the panel stays while other apps are used.
    /// When the panel last went away because something else was clicked.
    private var hiddenByClickElsewhere: ContinuousClock.Instant?
    /// When the panel last lost the keyboard to something else, until it's known what: a click
    /// elsewhere, or a swipe to another Space.
    private var lostKeyboard: ContinuousClock.Instant?
    /// When something other than the panel was last clicked, and when the Space on screen last
    /// changed.
    private var clickedElsewhere: ContinuousClock.Instant?
    private var spaceChanged: ContinuousClock.Instant?
    /// Hear clicks outside the panel while it's up: in other apps, and in Bite's other windows.
    private var clickMonitors: [Any] = []
    /// Kept while the menu offering it is open.
    private var sharePicker: NSSharingServicePicker?
    /// Set while the panel goes, put away already: it takes no clicks or keys meanwhile.
    private var isClosing = false
    /// Counts closes, so one only finishes if nothing showed the panel again or closed it since.
    private var closes = 0
    /// The panel shrinks a little as it goes (see `closeAway`). Off for tests, which look
    /// straight after.
    private lazy var animatesClosing = !forTesting
    /// How many times as long the panel takes to go: 1 but in tests.
    private var closeSlowdown = 1.0

    static let topBarHeight = TopBar.height
    /// Over every app's windows, their floating ones too, and over the Dock (user, 2026-10-05).
    /// Menus, an input method's candidates and help tags are higher still, over it.
    static let level = NSWindow.Level.statusBar
    /// Bite's other windows, over the panel: Settings (user, 2026-10-05), and AppKit's spelling
    /// panels, which float, under it.
    static let levelAbove = NSWindow.Level(rawValue: level.rawValue + 1)

    /// A panel for a test leaves the app in use active, and hears neither the person's clicks nor
    /// their Spaces changing: the tests run while they work.
    private let forTesting: Bool

    init(store: DotStore, forTesting: Bool = false) {
        self.store = store
        self.forTesting = forTesting
        pages = PanelPages(store: store, size: Self.savedSize)
        // For the share extension, its pages as big, kept since before it was. Not a test's.
        if !forTesting {
            Preferences.copy?.set(NSStringFromSize(Self.savedSize), forKey: PanelPages.sizeKey)
        }
        // A panel that doesn't activate Bite. Asked to, the system often wouldn't make Bite active
        // for a click on the ring, which a process of its own draws: the panel then never had the
        // keyboard, and never heard it should go away.
        panel = BitePanel(contentRect: NSRect(origin: .zero, size: Self.savedSize),
                          styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: true)
        super.init()
        panel.activatesBite = !forTesting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 280)
        panel.level = Self.level
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        panel.contentView = background
        pages.isShown = { [weak self] in self?.isShown ?? false }
        pages.addTopBar(PanelTopBar(store: store, onScreen: pages.onScreen) { [weak self] ink in
            CloseButton(placement: self?.placement, ink: ink) { self?.hide() }
        } trailing: { [weak self] ink in
            MenuButton(ink: ink) { anchor in self?.showMenu(below: anchor) }
        })
        addResizeCorner()
        panel.onFirstResponderChange = { [weak self] responder in
            self?.linkCard.keysWent(to: responder)
        }
        store.revealInEditor = { [weak self] dot, line, query in
            self?.reveal(dot: dot, line: line, query: query)
        }
        store.showInEditor = { [weak self] dot in
            self?.bringUp(dot)
        }
        if !forTesting {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange),
                                                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }
    }

    /// The link card's rows type in its own editor, in the page's colours.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        linkCard.owns(client) ? linkCard.fieldEditor : nil
    }

    func windowDidResize(_ notification: Notification) {
        pages.panelDidResize()
    }

    private func addResizeCorner() {
        let corner = ResizeCorner(frame: NSRect(x: background.bounds.maxX - 18, y: background.bounds.maxY - 18, width: 18, height: 18))
        corner.autoresizingMask = [.minXMargin, .minYMargin]
        corner.didResize = { [weak self] in
            self?.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        }
        background.addSubview(corner)
    }

    /// Two fingers sliding sideways on a trackpad move through the pages (see `PanelPages`).
    func takesScroll(_ event: NSEvent) -> Bool {
        pages.takesScroll(event)
    }

    func showSwipe(page: Int, offset: CGFloat) {
        pages.showSwipe(page: page, offset: offset)
    }

    func land(on page: Int) {
        pages.land(on: page)
    }

    /// A line picked in Spotlight: the panel comes up on its page, with the line in view and lit
    /// from its first frame.
    private func reveal(dot: Int, line: Int?, query: String) {
        bringUp(dot)
        controllers[dot].reveal(query, line: line)
    }

    /// The panel comes up on `dot`'s page, picked already, as Siri or Spotlight asked.
    private func bringUp(_ dot: Int) {
        if isShown {
            pages.showPage(dot)
        } else {
            show()
        }
    }

    // MARK: Showing and hiding

    /// Up, and not on its way out.
    var isShown: Bool {
        panel.isVisible && !isClosing
    }

    #if DEBUG
    var windowForTesting: BitePanel {
        panel
    }

    var linkCardForTesting: LinkCard {
        linkCard
    }

    var linkBubbleForTesting: LinkBubble {
        linkBubble
    }

    var linkShieldForTesting: LinkShield {
        linkShield
    }

    /// As the pointer coming onto `link` does, or going from a link to `point` in the window, far
    /// from it by default.
    func hoverForTesting(_ link: EditorController.PageLink?, on page: EditorController, at point: NSPoint = NSPoint(x: -1000, y: -1000)) {
        pages.pointerMoved(to: point, over: link, on: page)
    }

    /// Goes as it does for the person, for a test of it going, `slowdown` times as slow, to look at
    /// it partway.
    func animateClosingForTesting(slowdown: Double = 1) {
        animatesClosing = true
        closeSlowdown = slowdown
    }

    var isClosingForTesting: Bool {
        background.layer?.animation(forKey: Self.closeKey) != nil
    }

    /// Whether the panel's shrink was handed to Core Animation as it was put away.
    var closeHasBegunForTesting: Bool {
        (background.layer?.animation(forKey: Self.closeKey)?.beginTime ?? 0) > 0
    }

    var backgroundIsGlassForTesting: Bool {
        background.showsGlass
    }
    #endif

    func toggle() {
        if isShown {
            hide()
        } else if let hidden = hiddenByClickElsewhere, ContinuousClock.now - hidden < .milliseconds(400) {
            // The press on the ring took the panel's keyboard a moment ago, which put it away:
            // that was the click closing it, not one opening it again.
            return
        } else {
            show()
        }
    }

    /// Called as the panel comes up, and as it goes.
    var onVisibleChange: (Bool) -> Void = { _ in }

    func show() {
        pages.storeDidChange()
        if !placement.isDetached { position() }
        onVisibleChange(true)
        // Hidden to give the app in use back the keyboard (see `hide`).
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        stopClosing()
        // AppKit gives a window coming up a quick, slight zoom of its own.
        panel.makeKeyAndOrderFront(nil)
        controllers[store.selection].focus()
        statusItem?.isHighlighted = true
        panel.invalidateShadow()
        // Only the active app sets the pointer, so until Bite is, it stays an arrow over the text.
        // The system may say no to this; a click or a key in the panel then does it (`BitePanel`).
        guard !forTesting else { return }
        NSApp.activate()
        hearClicks()
    }

    private func hearClicks() {
        guard clickMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) {
            clickMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.clickedOutside() }
            }
            return event
        }) {
            clickMonitors.append(monitor)
        }
    }

    /// The ring gets its place in the menu bar a moment after the app starts. Shown before, the
    /// panel would have nothing to sit under.
    func showOnceRingIsPlaced(tries: Int = 30) {
        guard tries > 0, statusItem?.button?.window.map({ $0.frame.height == 0 }) ?? false else {
            show()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showOnceRingIsPlaced(tries: tries - 1)
        }
    }

    /// Closed, a panel dragged away from the ring goes back below it next time.
    func hide() {
        guard isShown else { return }
        // A link being changed is kept as typed, as when the keys go anywhere else.
        if linkCard.isEditingLink { linkCard.finish() }
        pages.hideBubble()
        store.saveNow()
        onVisibleChange(false)
        placement.isDetached = false
        statusItem?.isHighlighted = false
        stopHearingClicks()
        closeAway()
        // Back to the app that was in use, unless another window of Bite's is. Bite gives it back by
        // hiding: told to deactivate, it stayed active with nothing on screen, and typing went
        // nowhere. It does so at once, so typing goes there even while the panel goes.
        if !forTesting, NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey && $0 !== panel }) {
            NSApp.hide(nil)
        }
    }

    /// Another window of Bite's, Settings, is coming up in front.
    func hideForOtherWindow() {
        guard !placement.isDetached, isShown else { return }
        store.saveNow()
        onVisibleChange(false)
        statusItem?.isHighlighted = false
        stopHearingClicks()
        closeAway()
    }

    /// The panel goes with a quick, slight shrink about its middle, as it came: AppKit brings it
    /// up whole at 98.3% of its size and grows it to its full size in 90 ms (recorded frame by
    /// frame), and animates nothing going, even for `close()`. Going, it shrinks back to that
    /// size, quickly at first, as it clears, slowly at first, its shadow with it, as quick as it
    /// came: it's seen to shrink, and then to go.
    ///
    /// The user found 0.1 s to 98.5%, clearing only in its last 30 ms and its shadow then all at
    /// once, too quick and sudden, a blink: the shadow going in one frame was most of it. Clearing
    /// all the way, shadow and all, it was perfect, and the shrink went back to the opening's
    /// (2026-10-05). A 0.18 s fade with no shrink was too slow and not what they meant
    /// (2026-10-03). The shrink played backwards, easing in, stood still for its first 25 ms, and
    /// sat shrunk 30 ms more before the window went.
    private static let closeDuration: CFTimeInterval = 0.1
    private static let closeScale: CGFloat = 0.983
    private static let closeKey = "close"

    /// Put away already: Bite hiding leaves the panel on screen meanwhile, taking neither clicks
    /// nor keys, and it's gone once it has cleared.
    ///
    /// Core Animation plays the shrink, frame by frame in its own process, whatever Bite is doing:
    /// Bite hides at once. Stepped from here, it started a few frames late and didn't run smoothly.
    /// It's handed over at once, too: left to go with the rest of this turn, it waited on Bite
    /// hiding, 13 ms. The window's shadow follows the panel's shape as it shrinks, but not its
    /// opacity, so the window clears, which AppKit steps from here, Bite hidden or not.
    private func closeAway() {
        closes += 1
        let close = closes
        isClosing = true
        panel.ignoresMouseEvents = true
        panel.isClosing = true
        panel.canHide = false
        guard animatesClosing, let layer = background.layer else {
            finishClosing()
            return
        }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.toValue = NSValue(caTransform3D: scaled(layer, by: Self.closeScale))
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = Self.closeDuration * closeSlowdown
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: Self.closeKey)
        CATransaction.flush()
        // The window clears, not the panel in it: the window's shadow, drawn outside, stayed dark
        // as the panel cleared and went with the window all at once. It goes once it's clear;
        // gone when the shrink was done, it was still a little there.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closeDuration * closeSlowdown
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.closes == close, self.isClosing else { return }
                self.finishClosing()
            }
        }
        // In case the animation never says it's done.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration * closeSlowdown + 0.15) { [weak self] in
            guard let self, self.closes == close, self.isClosing else { return }
            self.finishClosing()
        }
    }

    private func finishClosing() {
        isClosing = false
        panel.orderOut(nil)
        resetAfterClosing()
        panel.alphaValue = 1
        // Found text has had its moment: it's gone when the panel's back.
        for controller in controllers {
            controller.textView.hideFound(.atOnce)
        }
    }

    /// Shown again while it goes, it's back as it was at once.
    private func stopClosing() {
        closes += 1
        isClosing = false
        resetAfterClosing()
        // Clear partway, it's back whole at once.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    private func resetAfterClosing() {
        background.layer?.removeAnimation(forKey: Self.closeKey)
        panel.ignoresMouseEvents = false
        panel.isClosing = false
        panel.canHide = true
    }

    /// `layer` drawn at `scale` of its size, about its middle: from where it turns, over to the
    /// middle and back.
    private func scaled(_ layer: CALayer, by scale: CGFloat) -> CATransform3D {
        let bounds = layer.bounds
        let pivot = CGPoint(x: bounds.minX + layer.anchorPoint.x * bounds.width, y: bounds.minY + layer.anchorPoint.y * bounds.height)
        let offset = CGPoint(x: bounds.midX - pivot.x, y: bounds.midY - pivot.y)
        var transform = CATransform3DMakeTranslation(offset.x, offset.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -offset.x, -offset.y, 0)
    }

    private func stopHearingClicks() {
        lostKeyboard = nil
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    /// How far apart the keyboard going and what took it can come, in either order.
    private static let causeWindow: Duration = .milliseconds(500)

    /// Something else took the keyboard. A click elsewhere, on another app, the desktop or a
    /// window of Bite's own, puts the panel away. A swipe to another Space doesn't: the panel is
    /// there too, and the keyboard stays with what the system gave it, as Command-Tab to an app
    /// on another Space also changes the Space. With neither, as for Command-Tab on this Space,
    /// it goes a moment later.
    func windowDidResignKey(_ notification: Notification) {
        guard isShown else { return }
        store.saveNow()
        guard !placement.isDetached else { return }
        let lost = ContinuousClock.now
        if let clicked = clickedElsewhere, lost - clicked < Self.causeWindow {
            putAway()
        } else if let changed = spaceChanged, lost - changed < Self.causeWindow {
            return
        } else {
            lostKeyboard = lost
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
                guard let self, self.lostKeyboard == lost, !self.panel.isKeyWindow else { return }
                self.putAway()
            }
        }
    }

    /// Something other than the panel was clicked. That puts the panel away even when it doesn't
    /// have the keyboard, as after a swipe to another Space. With it, the click takes it, which
    /// does the same (see `windowDidResignKey`).
    func clickedOutside() {
        clickedElsewhere = .now
        guard !placement.isDetached, isShown, !panel.isKeyWindow else { return }
        putAway()
    }

    /// The panel is being dragged by its top: it comes away from the ring. AppKit says so only for
    /// a drag, not for the panel put in place or resized.
    func windowWillMove(_ notification: Notification) {
        guard panel.isVisible, !isPositioning else { return }
        placement.isDetached = true
    }

    /// Up but covered, or with the screen locked or asleep, the panel isn't on screen.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        onVisibleChange(isShown && panel.occlusionState.contains(.visible))
    }

    /// The panel shows on every Space. Changed to just now, the Space took the keyboard, and the
    /// panel stays.
    @objc func activeSpaceDidChange() {
        spaceChanged = .now
        lostKeyboard = nil
    }

    private func putAway() {
        hide()
        hiddenByClickElsewhere = .now
    }

    /// Just below the ring in the menu bar, kept on its screen. With no ring to be seen, at the
    /// right of the menu bar, where the ring would be.
    private func position() {
        var frame = panel.frame
        guard let button = statusItem?.button, let window = button.window, window.frame.height > 0,
              let screen = window.screen ?? NSScreen.main else {
            if let visible = NSScreen.main?.visibleFrame {
                frame.size.height = min(frame.height, visible.height - 16)
                frame.origin = NSPoint(x: visible.maxX - frame.width - 12, y: visible.maxY - frame.height - 6)
                isPositioning = true
                panel.setFrame(frame, display: false)
                isPositioning = false
            }
            return
        }
        let ring = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        frame.size.height = min(frame.height, visible.height - 16)
        frame.origin.x = min(max(ring.midX - frame.width / 2, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = max(min(ring.minY, visible.maxY) - frame.height - 6, visible.minY + 8)
        isPositioning = true
        panel.setFrame(frame, display: false)
        isPositioning = false
    }

    private static var savedSize: NSSize {
        PanelPages.savedSize(in: .standard)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        let size = NSStringFromSize(panel.frame.size)
        UserDefaults.standard.set(size, forKey: PanelPages.sizeKey)
        Preferences.copy?.set(size, forKey: PanelPages.sizeKey)
        panel.invalidateShadow()
    }

    // MARK: The menu

    /// The "…" menu: settings, the page's statistics and its own commands, and quitting.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = MenuRow.keyboard
        let dot = store.selection
        let hasText = !store.isEmpty[dot]
        menu.addItem(settingsItem())
        menu.addItem(statisticsItem(dot: dot))
        menu.addItem(.separator())
        menu.addItem(item("Copy Markdown", symbol: "doc.on.doc", action: #selector(copyMarkdown), isEnabled: hasText))
        menu.addItem(item("Copy Plain Text", symbol: "doc.plaintext", action: #selector(copyPlainText), isEnabled: hasText))
        // Neither red nor asked about: the page is cleared as an edit, which undo brings back.
        menu.addItem(item("Clear Text", symbol: "eraser", action: #selector(clearText), isEnabled: hasText))
        menu.addItem(.separator())
        menu.addItem(item("Share Text", symbol: "square.and.arrow.up", action: #selector(shareText), isEnabled: hasText))
        menu.addItem(.separator())
        menu.addItem(quitItem())
        return menu
    }

    /// The ring's right click: Bite's own commands, none of the page's.
    func makeRingMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuRow.keyboard
        menu.addItem(settingsItem())
        menu.addItem(.separator())
        menu.addItem(quitItem())
        return menu
    }

    /// The page's words, characters and paragraphs, and when it last changed, as the phone's
    /// Statistics drawer shows them. Counted as the menu opens, with typing from a moment ago.
    private func statisticsItem(dot: Int) -> NSMenuItem {
        let statistics = PageStatistics(document: MarkdownParser.parse(store.currentMarkdown(dot: dot)))
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(MenuRow.info("Words", value: statistics.words.formatted()))
        submenu.addItem(MenuRow.info("Characters", value: statistics.characters.formatted()))
        submenu.addItem(MenuRow.info("Paragraphs", value: statistics.paragraphs.formatted()))
        if let modified = store.modified[dot] {
            submenu.addItem(.separator())
            submenu.addItem(MenuRow.info("Modified", value: ModifiedDate.text(modified)))
        }
        return MenuRow.item("Statistics", symbol: "chart.bar", submenu: submenu,
                            tint: NSColor(hex: DotPalette.colors[dot].light))
    }

    private func settingsItem() -> NSMenuItem {
        item("Settings…", symbol: "gearshape", key: ",", action: #selector(AppDelegate.showSettings(_:)), target: NSApp.delegate)
    }

    private func quitItem() -> NSMenuItem {
        item("Quit Bite", symbol: "power", key: "q", action: #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    /// With the phone's pictures, the keys the same commands have in Bite's menus, and the page's
    /// colour for the highlight (see `MenuRow`).
    private func item(_ title: String, symbol: String, key: String = "", action: Selector, target: AnyObject? = nil,
                      isEnabled: Bool = true) -> NSMenuItem {
        // The light appearance's colour, deeper than the dark's, in both: the row's title turns
        // white on it, as on AppKit's accent.
        let tint = NSColor(hex: DotPalette.colors[store.selection].light)
        return MenuRow.item(title, symbol: symbol, key: key, action: action, target: target ?? self, tint: tint,
                            isEnabled: isEnabled)
    }

    #if DEBUG
    func showMenuForSnapshot() {
        showMenu(below: menuButtonFrame)
    }

    func shareForSnapshot() {
        shareText()
    }

    /// The page's text right-clicked where it's selected, or at the caret: the text's own menu.
    func showTextMenuForSnapshot() {
        let view = controllers[store.selection].textView
        guard let window = view.window, let frame = view.anchorFrame(for: view.selectedRange()),
              let event = NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil),
                                             modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let menu = view.menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
    #endif

    /// The "…" button, in the top bar.
    private var menuButtonFrame: CGRect {
        let size = DotSwitcher.height
        return CGRect(x: (topBar?.bounds.maxX ?? 0) - TopBar.margin - size, y: TopBar.margin, width: size, height: size)
    }

    private func showMenu(below anchor: CGRect) {
        guard let topBar else { return }
        makeMenu().popUp(positioning: nil, at: NSPoint(x: anchor.minX, y: anchor.maxY + 6), in: topBar)
    }

    /// The system's share picker, below the "…" button. The share item AppKit makes for a menu did
    /// nothing from the panel's.
    @objc private func shareText() {
        guard let topBar else { return }
        let picker = NSSharingServicePicker(items: [store.currentMarkdown(dot: store.selection)])
        sharePicker = picker
        picker.show(relativeTo: menuButtonFrame, of: topBar, preferredEdge: .maxY)
    }

    @objc private func copyMarkdown() {
        Clipboard.string = store.currentMarkdown(dot: store.selection)
    }

    @objc private func copyPlainText() {
        Clipboard.string = store.currentPlainText(dot: store.selection)
    }

    @objc private func clearText() {
        store.clear(dot: store.selection)
        controllers[store.selection].focus()
    }

    /// ⌘1 to ⌘7, from the Dots menu.
    @objc func selectDot(_ sender: NSMenuItem) {
        store.selection = sender.tag
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectDot(_:)):
            menuItem.state = store.selection == menuItem.tag ? .on : .off
        default:
            break
        }
        return true
    }
}

/// A panel with no title bar that still takes typing. Esc and ⌘W put it away.
final class BitePanel: NSPanel {
    var onCancel: () -> Void = {}
    /// Called with the keys' new holder each time they move within the panel.
    var onFirstResponderChange: (NSResponder?) -> Void = { _ in }
    /// Set on Bite's panel (see `sendEvent`).
    var activatesBite = false
    /// Set while the panel goes, put away already: keys meant for the app in use don't land in it.
    var isClosing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click or a key in the panel makes Bite the active app, which the system allows for what's
    /// done in its window. Only the app in front sets the pointer: until then it stayed an arrow
    /// over the text, never the I-beam.
    override func sendEvent(_ event: NSEvent) {
        if isClosing, event.type == .keyDown || event.type == .keyUp { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
            if activatesBite, !Self.biteIsInFront { NSApp.activate() }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// Whether Bite is the app in front, as the system has it. With the panel keyed, AppKit said
    /// Bite was active while another app stayed in front, so it never asked to be, and the pointer
    /// stayed that app's arrow.
    private static var biteIsInFront: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Bite may not be the active app while the panel has the keyboard, and then its menus don't
    /// hear their shortcuts on their own: ⌘C, ⌘Z, ⌘B and ⌘1 to ⌘7 are handed to them here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    override func performClose(_ sender: Any?) {
        onCancel()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let did = super.makeFirstResponder(responder)
        if did { onFirstResponderChange(firstResponder) }
        return did
    }
}

/// The page: the window's background washed with the dot's colour, as on the phone, in a shape
/// with rounded corners.
/// The panel's bottom right corner, dragged to make it larger or smaller. The top stays where it
/// is, under the menu bar.
final class ResizeCorner: NSView {
    var didResize: () -> Void = {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation
        let startFrame = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let location = NSEvent.mouseLocation
            var frame = startFrame
            frame.size.width = max(window.minSize.width, startFrame.width + location.x - start.x)
            frame.size.height = max(window.minSize.height, startFrame.height - (location.y - start.y))
            frame.origin.y = startFrame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
        window.invalidateShadow()
        didResize()
    }
}
