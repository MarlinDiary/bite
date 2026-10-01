import AppKit
import SwiftUI
import BiteKit

/// The panel the ring in the menu bar opens, just below it: the dot bar over the page of the
/// dot picked. It takes typing even while the system won't make Bite the active app, and goes
/// away as soon as anything else is clicked. A swipe to another Space takes it along. Dragged by
/// its top, it comes away from the ring and stays where it's put until it's closed.
final class PanelController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let store: DotStore
    let controllers: [EditorController]
    weak var statusItem: StatusItemController?

    private let panel: BitePanel
    private let background = PageBackgroundView()
    private var scrollViews: [PageScrollView] = []
    /// The page mostly on screen while a swipe moves between two, which the dot bar follows.
    let onScreen = PageOnScreen()
    let placement = PanelPlacement()
    /// Set while the panel is put below the ring, which isn't a drag taking it away.
    private var isPositioning = false
    private var topBar: NSHostingView<TopBar>?
    private var shownPage: Int?
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

    static let topBarHeight = TopBar.height
    private static let sizeKey = "panelSize"

    /// A panel for a test leaves the app in use active, and hears neither the person's clicks nor
    /// their Spaces changing: the tests run while they work.
    private let forTesting: Bool

    init(store: DotStore, forTesting: Bool = false) {
        self.store = store
        self.forTesting = forTesting
        controllers = DotPalette.colors.indices.map { EditorController(dot: $0, accent: DotPalette.colors[$0].platformColor) }
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
        panel.level = .floating
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        background.frame = NSRect(origin: .zero, size: Self.savedSize)
        panel.contentView = background
        addPages()
        addTopBar()
        addResizeCorner()
        store.reportPendingEdits = { [weak self] in
            self?.controllers.forEach { $0.reportPendingChange() }
        }
        store.applyInEditor = { [weak self] dot, markdown in
            self?.controllers[dot].applyRemote(markdown: markdown)
        }
        store.clearInEditor = { [weak self] dot in
            self?.controllers[dot].clear()
        }
        storeDidChange()
        observeStore()
        if !forTesting {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange),
                                                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }
    }

    private func addPages() {
        for controller in controllers {
            let dot = controller.dot
            let store = store
            controller.onChange = { markdown in
                store.update(dot: dot, markdown: markdown)
            }
            controller.onEmptyChange = { isEmpty in
                store.update(dot: dot, isEmpty: isEmpty)
            }
            controller.load(markdown: store.markdown[dot])
            controller.loadedRevision = store.revisions[dot]

            let scrollView = PageScrollView(frame: background.bounds)
            scrollView.takesScroll = { [weak self] event in self?.takesScroll(event) ?? false }
            scrollView.autoresizingMask = [.width, .height]
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            // The page draws its own indicator (see `PageScrollView`).
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            // The text scrolls on under the dot bar, as on the phone.
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = NSEdgeInsets(top: Self.topBarHeight, left: 0, bottom: 14, right: 0)
            // Clear of the dot bar.
            scrollView.findBarPosition = .belowContent
            let textView = controller.textView
            textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
            textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
            scrollView.documentView = textView
            scrollView.isHidden = true
            background.addSubview(scrollView)
            scrollViews.append(scrollView)
        }
    }

    private func addTopBar() {
        background.takesScroll = { [weak self] event in self?.takesScroll(event) ?? false }
        let topBar = NSHostingView(rootView: TopBar(store: store, onScreen: onScreen, placement: placement) { [weak self] in
            self?.hide()
        } showMenu: { [weak self] anchor in
            self?.showMenu(below: anchor)
        })
        // The bar fits the panel; it never sizes the panel to fit itself.
        topBar.sizingOptions = []
        topBar.frame = NSRect(x: 0, y: 0, width: background.bounds.width, height: Self.topBarHeight)
        topBar.autoresizingMask = [.width, .maxYMargin]
        background.addSubview(topBar)
        self.topBar = topBar
    }

    private func addResizeCorner() {
        let corner = ResizeCorner(frame: NSRect(x: background.bounds.maxX - 18, y: background.bounds.maxY - 18, width: 18, height: 18))
        corner.autoresizingMask = [.minXMargin, .minYMargin]
        corner.didResize = { [weak self] in
            self?.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification))
        }
        background.addSubview(corner)
    }

    // MARK: The store

    /// Follows the dot picked, and pages changed outside their editors.
    private func observeStore() {
        withObservationTracking {
            _ = store.selection
            _ = store.revisions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.storeDidChange()
                self?.observeStore()
            }
        }
    }

    private func storeDidChange() {
        for controller in controllers where controller.loadedRevision != store.revisions[controller.dot] {
            controller.loadedRevision = store.revisions[controller.dot]
            controller.load(markdown: store.markdown[controller.dot])
        }
        showPage(store.selection)
    }

    private func showPage(_ page: Int) {
        guard page != shownPage, controllers.indices.contains(page) else { return }
        shownPage = page
        for (index, scrollView) in scrollViews.enumerated() {
            scrollView.isHidden = index != page
        }
        background.accent = DotPalette.colors[page].platformColor
        if panel.isVisible {
            controllers[page].focus()
        }
    }

    // MARK: Swiping between pages

    private let swiper = PageSwiper(pageCount: DotPalette.count)
    /// Steps the spring each frame while the pages settle.
    private var settling: CADisplayLink?
    /// Whether the scroll gesture under way has shown which way it goes.
    private var gestureIsDecided = false

    /// Two fingers sliding sideways on a trackpad move through the pages, as a finger does on the
    /// phone (see `PageSwiper`). A scroll that starts out more up or down than sideways is the
    /// page's own, as is any from a mouse. The system's "swipe between pages" setting decides.
    func takesScroll(_ event: NSEvent) -> Bool {
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled, event.hasPreciseScrollingDeltas else { return false }
        let phase = event.phase
        if swiper.isTracking {
            // Momentum from before the pages were caught is the spring's to carry, not the fingers'.
            guard event.momentumPhase.isEmpty else { return true }
            if phase.contains(.ended) || phase.contains(.cancelled) {
                swiper.release(at: event.timestamp, springStart: CACurrentMediaTime())
                startSettling()
            } else {
                swiper.track(event.scrollingDeltaX, at: event.timestamp)
            }
            layOutSwipe()
            return true
        }
        if swiper.isSettling {
            // Fingers down again catch the pages where they are.
            if phase.contains(.mayBegin) || phase.contains(.began) {
                stopSettling()
                swiper.catchPages()
            }
            return true
        }
        guard event.momentumPhase.isEmpty else { return false }
        if phase.contains(.began) { gestureIsDecided = false }
        guard !gestureIsDecided, phase.contains(.began) || phase.contains(.changed) else { return false }
        let across = abs(event.scrollingDeltaX), down = abs(event.scrollingDeltaY)
        guard across + down > 0 else { return false }
        gestureIsDecided = true
        guard across > down else { return false }
        swiper.width = background.bounds.width
        swiper.begin(on: store.selection)
        swiper.track(event.scrollingDeltaX, at: event.timestamp)
        layOutSwipe()
        return true
    }

    private func startSettling() {
        guard settling == nil else { return }
        let link = background.displayLink(target: self, selector: #selector(stepSettling(_:)))
        link.add(to: .main, forMode: .common)
        settling = link
    }

    private func stopSettling() {
        settling?.invalidate()
        settling = nil
    }

    @objc private func stepSettling(_ link: CADisplayLink) {
        let landed = swiper.step(to: link.targetTimestamp)
        layOutSwipe()
        if let landed {
            stopSettling()
            land(on: landed)
        }
    }

    private func layOutSwipe() {
        showSwipe(page: swiper.page, offset: swiper.shownOffset)
    }

    /// `page` moved `offset` points right, and the page beside it in the room that leaves. The
    /// dot bar and the wash follow the page mostly on screen.
    func showSwipe(page: Int, offset: CGFloat) {
        let width = background.bounds.width
        let beside = offset > 0 ? page - 1 : page + 1
        let hasBeside = offset != 0 && controllers.indices.contains(beside)
        for (index, scrollView) in scrollViews.enumerated() {
            if index == page {
                scrollView.frame.origin.x = offset
                scrollView.isHidden = false
            } else if hasBeside, index == beside {
                scrollView.frame.origin.x = offset + (offset > 0 ? -width : width)
                scrollView.isHidden = false
            } else {
                scrollView.isHidden = true
            }
        }
        let visible = hasBeside && abs(offset) > width / 2 ? beside : page
        guard visible != onScreen.page ?? store.selection else { return }
        onScreen.page = visible
        // One tick for each dot passed, as on the phone.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.allowsImplicitAnimation = true
            background.accent = DotPalette.colors[visible].platformColor
        }
    }

    /// The pages have settled on `page`.
    func land(on page: Int) {
        onScreen.page = nil
        for scrollView in scrollViews {
            scrollView.frame.origin.x = 0
        }
        shownPage = nil
        store.selection = page
        showPage(page)
    }

    // MARK: Showing and hiding

    var isShown: Bool {
        panel.isVisible
    }

    #if DEBUG
    var windowForTesting: BitePanel {
        panel
    }
    #endif

    func toggle() {
        if panel.isVisible {
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
        storeDidChange()
        if !placement.isDetached { position() }
        onVisibleChange(true)
        // Hidden to give the app in use back the keyboard (see `hide`).
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
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
        guard panel.isVisible else { return }
        store.saveNow()
        panel.orderOut(nil)
        onVisibleChange(false)
        placement.isDetached = false
        statusItem?.isHighlighted = false
        stopHearingClicks()
        // Back to the app that was in use, unless another window of Bite's is. Bite gives it back by
        // hiding: told to deactivate, it stayed active with nothing on screen, and typing went
        // nowhere.
        if !forTesting, NSApp.isActive, !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey && $0 !== panel }) {
            NSApp.hide(nil)
        }
    }

    /// Another window of Bite's, Settings, is coming up in front.
    func hideForOtherWindow() {
        guard !placement.isDetached, panel.isVisible else { return }
        store.saveNow()
        panel.orderOut(nil)
        onVisibleChange(false)
        statusItem?.isHighlighted = false
        stopHearingClicks()
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
        guard panel.isVisible else { return }
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
        guard !placement.isDetached, panel.isVisible, !panel.isKeyWindow else { return }
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
        onVisibleChange(panel.isVisible && panel.occlusionState.contains(.visible))
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
        let size = NSSizeFromString(UserDefaults.standard.string(forKey: sizeKey) ?? "")
        return size.width >= 320 && size.height >= 280 ? size : NSSize(width: 400, height: 560)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: Self.sizeKey)
        panel.invalidateShadow()
    }

    // MARK: The menu

    /// The "…" menu: settings, the page's own commands, and quitting.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let dot = store.selection
        let hasText = !store.isEmpty[dot]
        menu.addItem(settingsItem())
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
        menu.addItem(settingsItem())
        menu.addItem(.separator())
        menu.addItem(quitItem())
        return menu
    }

    private func settingsItem() -> NSMenuItem {
        item("Settings…", symbol: "gearshape", key: ",", action: #selector(AppDelegate.showSettings(_:)), target: NSApp.delegate)
    }

    private func quitItem() -> NSMenuItem {
        item("Quit Bite", symbol: "power", key: "q", action: #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    /// With the phone's pictures, and the keys the same commands have in Bite's menus.
    private func item(_ title: String, symbol: String, key: String = "", action: Selector, target: AnyObject? = nil,
                      isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.isEnabled = isEnabled
        show(symbol, on: item)
        return item
    }

    /// Since macOS 27, AppKit hides a menu item's picture unless it's asked to show it.
    private func show(_ symbol: String, on item: NSMenuItem) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if #available(macOS 27, *) {
            item.preferredImageVisibility = .visible
        }
    }

    #if DEBUG
    func showMenuForSnapshot() {
        showMenu(below: menuButtonFrame)
    }

    func shareForSnapshot() {
        shareText()
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
    /// Set on Bite's panel (see `sendEvent`).
    var activatesBite = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click or a key in the panel makes Bite the active app, which the system allows for what's
    /// done in its window. Only the active app sets the pointer: until then it stayed an arrow
    /// over the text, never the I-beam.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
            if activatesBite, !NSApp.isActive { NSApp.activate() }
        default:
            break
        }
        super.sendEvent(event)
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
}

/// The page: the window's background washed with the dot's colour, as on the phone, in a shape
/// with rounded corners.
final class PageBackgroundView: NSView {
    var accent: NSColor = .clear {
        didSet { updateColors() }
    }
    /// A swipe that starts over the dot bar comes here.
    var takesScroll: (NSEvent) -> Bool = { _ in false }

    override func scrollWheel(with event: NSEvent) {
        if takesScroll(event) { return }
        super.scrollWheel(with: event)
    }
    private let wash = NSView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = TopBar.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        wash.wantsLayer = true
        wash.frame = bounds
        wash.autoresizingMask = [.width, .height]
        addSubview(wash)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            wash.layer?.backgroundColor = accent.withAlphaComponent(PageTint.opacity(dark: effectiveAppearance.isDark)).cgColor
        }
    }
}

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

/// A page's scroll view. It lets the panel take a scroll that swipes to another page, and draws
/// its own scroll indicator.
final class PageScrollView: NSScrollView {
    var takesScroll: (NSEvent) -> Bool = { _ in false }

    override func scrollWheel(with event: NSEvent) {
        if takesScroll(event) { return }
        lastScrollByHand = CACurrentMediaTime()
        super.scrollWheel(with: event)
    }

    // MARK: Scroll indicator

    /// As on the phone: a thin bar that shows only while the page is scrolled by hand, and fades
    /// soon after. AppKit's scroller came up whenever it saw fit, as when a page came back on
    /// screen without being scrolled at all.
    private let indicator = CALayer()
    private var lastScrollByHand: CFTimeInterval = 0
    private var fade: DispatchWorkItem?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateIndicator()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateIndicator()
    }

    private func updateIndicator() {
        guard let layer, let document = documentView else { return }
        if indicator.superlayer !== layer || layer.sublayers?.last !== indicator {
            indicator.removeFromSuperlayer()
            layer.addSublayer(indicator)
            indicator.opacity = 0
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // From just under the dot bar to above where the panel's corner starts to curve.
        let top = contentInsets.top + 2
        let bottom = max(top, bounds.height - TopBar.cornerRadius)
        let track = bottom - top
        let visible = contentView.bounds.height - contentInsets.top - contentInsets.bottom
        let total = document.frame.height
        guard total > visible + 1, track > 0 else {
            indicator.opacity = 0
            return
        }
        let range = total - visible
        let scrolled = contentView.bounds.minY + contentInsets.top
        // Pulled past either end, the bar shortens, as the phone's does.
        let past = max(-scrolled, scrolled - range, 0)
        let length = max(8, max(36, track * visible / total) - past)
        let progress = min(max(scrolled / range, 0), 1)
        let width: CGFloat = 3
        let y = top + (track - length) * progress
        indicator.frame = CGRect(x: bounds.width - width - 3, y: isFlipped ? y : bounds.height - y - length, width: width, height: length)
        indicator.cornerRadius = width / 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            indicator.backgroundColor = NSColor.labelColor.withAlphaComponent(0.3).cgColor
        }
        guard CACurrentMediaTime() - lastScrollByHand < 0.3 else { return }
        indicator.opacity = 1
        fade?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            indicator.opacity = 0
            CATransaction.commit()
        }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    #if DEBUG
    func showIndicatorForSnapshot() {
        lastScrollByHand = CACurrentMediaTime()
        updateIndicator()
    }
    #endif
}

/// The page the dot bar shows as picked while a swipe is between two; nil otherwise.
@Observable
final class PageOnScreen {
    var page: Int?
}

/// Whether the panel has been dragged away from the ring, to stand on its own until it's closed.
@Observable
final class PanelPlacement {
    var isDetached = false
}
