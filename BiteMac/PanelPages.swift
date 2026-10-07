import AppKit
import SwiftUI
import BiteKit

/// The pages as Bite's panel shows them: each page's editor in a scroll view over the page's
/// colour, the dot bar along the top, two fingers sliding sideways moving through the pages, and a
/// link's pill and card floating by it. The panel's (see `PanelController`), and the share
/// extension's, so a page shared to looks just as it does in Bite.
@MainActor
final class PanelPages: NSObject {
    let store: DotStore
    let controllers: [EditorController]
    /// The pages, in their colour, and everything over them.
    let background = PageBackgroundView()
    private var scrollViews: [PageScrollView] = []
    /// The page mostly on screen while a swipe moves between two, which the dot bar follows.
    let onScreen = PageOnScreen()
    private(set) var topBar: NSView?
    /// A link being changed, in a card floating by it.
    let linkCard = LinkCard()
    /// A link under the pointer, with Edit on it.
    let linkBubble = LinkBubble()
    /// Where the pill's link is drawn, while the pill is up: the pointer between the two keeps it.
    private var bubbleLinkFrame = NSRect.zero
    /// Over the page while the card is up.
    let linkShield = LinkShield()
    private var shownPage: Int?
    /// Whether the pages are up, for the page picked to take the keys.
    var isShown: () -> Bool = { false }

    static let topBarHeight = TopBar.height

    /// Where the panel's size is kept: in Bite's own defaults, and with its copy of its settings,
    /// for the share extension, whose pages are as big as the panel's.
    static let sizeKey = "panelSize"

    /// The size the panel was last left at, kept in `defaults`: as Bite first opens it, otherwise.
    static func savedSize(in defaults: UserDefaults?) -> NSSize {
        let size = NSSizeFromString(defaults?.string(forKey: sizeKey) ?? "")
        return size.width >= 320 && size.height >= 280 ? size : NSSize(width: 400, height: 560)
    }

    init(store: DotStore, size: NSSize) {
        self.store = store
        controllers = DotPalette.colors.indices.map { EditorController(dot: $0, accent: DotPalette.colors[$0].platformColor) }
        super.init()
        background.frame = NSRect(origin: .zero, size: size)
        addPages()
        store.reportPendingEdits = { [weak self] in
            self?.controllers.forEach { $0.reportPendingChange() }
        }
        store.applyInEditor = { [weak self] dot, markdown in
            self?.controllers[dot].applyRemote(markdown: markdown)
        }
        store.clearInEditor = { [weak self] dot in
            self?.controllers[dot].clear()
        }
        store.showEndInEditor = { [weak self] dot in
            self?.controllers[dot].showEnd()
        }
        store.pageIsAtEnd = { [weak self] dot in
            self?.controllers[dot].isAtEnd ?? true
        }
        storeDidChange()
        observeStore()
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
            controller.onEditLink = { [weak self, weak controller] link in
                guard let self, let controller else { return }
                self.hideBubble()
                self.linkCard.edit(link, on: controller)
            }
            controller.textView.onLinkHover = { [weak self, weak controller] link, point in
                guard let self, let controller else { return }
                self.pointerMoved(to: point, over: link, on: controller)
            }

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
            // The pill goes as the page scrolls, and the card goes along with its link.
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(pageScrolled), name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }
    }

    /// The dot bar along the top, with the buttons at its ends that `bar` puts there, and over it
    /// all, a link's card and pill.
    func addTopBar<Bar: View>(_ bar: Bar) {
        background.takesScroll = { [weak self] event in self?.takesScroll(event) ?? false }
        let topBar = NSHostingView(rootView: bar)
        // The bar fits the panel; it never sizes the panel to fit itself.
        topBar.sizingOptions = []
        topBar.frame = NSRect(x: 0, y: 0, width: background.bounds.width, height: Self.topBarHeight)
        topBar.autoresizingMask = [.width, .maxYMargin]
        background.addSubview(topBar)
        self.topBar = topBar
        addLinkCard()
    }

    /// The link card and the pill, floating over the pages by a link. The keys going from the card
    /// anywhere else leave the link as typed (see `LinkCard`).
    private func addLinkCard() {
        linkShield.isHidden = true
        linkShield.frame = background.bounds
        linkShield.autoresizingMask = [.width, .height]
        linkShield.onClick = { [weak self] in self?.linkCard.finish() }
        background.addSubview(linkShield)
        linkCard.isHidden = true
        linkCard.topClearance = Self.topBarHeight + LinkCard.margin
        linkCard.onShownChange = { [weak self] shown in
            guard let self else { return }
            self.linkShield.isHidden = !shown
            self.background.window?.invalidateCursorRects(for: self.linkShield)
        }
        background.addSubview(linkCard)
        linkBubble.isHidden = true
        background.addSubview(linkBubble)
        linkBubble.onEdit = { [weak self] link, page in
            guard let self else { return }
            // The pill goes at once, the card coming in its place.
            self.linkBubble.hideNow()
            self.linkCard.edit(link, on: page)
        }
        linkBubble.onHoverChange = { [weak self] onIt, point in
            guard let self, !onIt else { return }
            self.pointerMoved(to: point, over: nil, on: nil)
        }
    }

    /// The pointer is at `point`, in the window, over `link` on `page` or over none: the pill
    /// comes as the pointer comes onto a link, and goes as it leaves, unless it's between the
    /// link and the pill, on its way there.
    func pointerMoved(to point: NSPoint, over link: EditorController.PageLink?, on page: EditorController?) {
        guard !linkCard.isEditingLink else { return }
        if let link, let page {
            if linkBubble.isShown, linkBubble.link == link { return }
            showBubble(for: link, on: page)
        } else if linkBubble.isShown {
            let zone = bubbleLinkFrame.union(linkBubble.frame).insetBy(dx: -4, dy: -4)
            if zone.contains(background.convert(point, from: nil)) { return }
            hideBubble()
        }
    }

    private func showBubble(for link: EditorController.PageLink, on page: EditorController) {
        guard !linkCard.isEditingLink, let drawn = page.textView.anchorFrame(for: link.range) else { return }
        let anchor = background.convert(drawn, from: page.textView)
        bubbleLinkFrame = anchor
        linkBubble.show(link, on: page, anchor: anchor, topClearance: Self.topBarHeight + LinkCard.margin)
    }

    func hideBubble() {
        linkBubble.hide()
    }

    @objc private func pageScrolled() {
        hideBubble()
        linkCard.place()
    }

    /// The panel changed size: the pill goes, and the card stays by its link.
    func panelDidResize() {
        hideBubble()
        linkCard.place()
    }

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

    /// Pages changed outside their editors go in again, and the page picked is shown.
    func storeDidChange() {
        for controller in controllers where controller.loadedRevision != store.revisions[controller.dot] {
            controller.loadedRevision = store.revisions[controller.dot]
            controller.load(markdown: store.markdown[controller.dot])
        }
        showPage(store.selection)
    }
    /// Shows `page`, which, with the pages up, takes the keys.
    func showPage(_ page: Int) {
        guard page != shownPage, controllers.indices.contains(page) else { return }
        // A link being changed on the page left is kept as typed.
        if linkCard.isEditingLink { linkCard.finish() }
        hideBubble()
        shownPage = page
        for (index, scrollView) in scrollViews.enumerated() {
            scrollView.isHidden = index != page
        }
        background.accent = DotPalette.colors[page].platformColor
        if isShown() {
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
}

final class PageBackgroundView: NSView {
    var accent: NSColor = .clear {
        didSet { updateColors() }
    }
    /// Whether the pages have the panel's rounded corners and edge. The share sheet's are its
    /// window's: corners of the pages' own, inside them, made two.
    var drawsEdge = true {
        didSet { updateColors() }
    }
    /// A swipe that starts over the dot bar comes here.
    var takesScroll: (NSEvent) -> Bool = { _ in false }

    override func scrollWheel(with event: NSEvent) {
        if takesScroll(event) { return }
        super.scrollWheel(with: event)
    }
    private let wash = NSView()
    /// Chosen in Settings, the panel is thick frosted glass: what's behind it blurred, under the
    /// page's own background partway and the page's colour. Otherwise it's a page. It stays as it
    /// is while another app is in use. Liquid Glass, tried first, lost its tint then, and was thin.
    private let glass = NSVisualEffectView()
    /// Between the blur and the wash, the page's own background, partway, which makes the glass
    /// thick: the material alone was thin, or grey.
    private let frost = NSView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        frost.wantsLayer = true
        frost.frame = bounds
        frost.autoresizingMask = [.width, .height]
        addSubview(frost)
        wash.wantsLayer = true
        wash.frame = bounds
        wash.autoresizingMask = [.width, .height]
        addSubview(wash)
        updateColors()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange), name: Preferences.didChange, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var showsGlass: Bool { !glass.isHidden }

    @objc private func preferencesDidChange() {
        guard showsGlass != Preferences.panelIsGlass else { return }
        updateColors()
        // The shadow follows what's opaque.
        window?.invalidateShadow()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let isGlass = Preferences.panelIsGlass
        glass.isHidden = !isGlass
        frost.isHidden = !isGlass
        layer?.cornerRadius = drawsEdge ? TopBar.cornerRadius : 0
        layer?.borderWidth = drawsEdge && !isGlass ? 1 : 0
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.isDark
            layer?.backgroundColor = isGlass ? nil : NSColor.textBackgroundColor.cgColor
            frost.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(PageTint.glassFrost).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            let opacity = isGlass ? PageTint.glassOpacity(dark: dark) : PageTint.opacity(dark: dark)
            wash.layer?.backgroundColor = accent.withAlphaComponent(opacity).cgColor
        }
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

    // MARK: Fading under the dot bar

    /// The page fades out under the dot bar, clear at the panel's edge and whole where the bar
    /// ends, so text scrolled up under it doesn't crowd the dots. A page blurs as well as fades
    /// under a toolbar on macOS 26 (its scroll edge effect), but AppKit gives that only to
    /// titlebars, and nothing public blurs a page under a bar of one's own. The page's colour
    /// stays as it is, behind: only the text clears.
    private let edgeFade = CAGradientLayer()

    override func layout() {
        super.layout()
        updateEdgeFade()
    }

    private func updateEdgeFade() {
        guard let layer else { return }
        if layer.mask !== edgeFade { layer.mask = edgeFade }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        edgeFade.frame = layer.bounds
        // Mostly gone through the bar, and whole again where it ends: the square of the way down.
        let end = min(1, contentInsets.top / max(bounds.height, 1))
        let steps = [0, 0.25, 0.5, 0.75, 1.0]
        edgeFade.colors = steps.map { NSColor.black.withAlphaComponent($0 * $0).cgColor } + [NSColor.black.cgColor]
        edgeFade.locations = steps.map { NSNumber(value: $0 * end) } + [1]
        edgeFade.startPoint = CGPoint(x: 0.5, y: isFlipped ? 0 : 1)
        edgeFade.endPoint = CGPoint(x: 0.5, y: isFlipped ? 1 : 0)
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
