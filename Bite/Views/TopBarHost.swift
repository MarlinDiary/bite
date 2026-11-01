import SwiftUI
import UIKit
import BiteKit

/// Moves the dot bar up out of the way of the keys and back, with them. The bar is in a view of
/// UIKit's for this (see `TopBarHost`), so the move is Core Animation's, in the keys' own
/// animation, as the format bar's is. Moved by SwiftUI, the bar was gone in one frame as the keys
/// came up on the phone: SwiftUI animates a frame at a time on the main thread, which the keys
/// coming up hold for a moment there.
@MainActor
final class TopBarMover {
    fileprivate weak var view: UIView?
    /// How far up the bar goes, out of sight.
    fileprivate var lift: CGFloat = 0
    private(set) var isAway = false

    /// Called inside the keys' animation, which then carries the move.
    func move(away: Bool) {
        isAway = away
        guard let view else { return }
        view.alpha = away ? 0 : 1
        view.transform = away ? CGAffineTransform(translationX: 0, y: -lift) : .identity
    }

    #if DEBUG
    func attachForTesting(_ view: UIView, lift: CGFloat) {
        self.view = view
        self.lift = lift
    }
    #endif
}

/// The dot bar and the "…" button in a view controller of their own, which `TopBarMover` moves.
struct TopBarHost<Content: View>: UIViewControllerRepresentable {
    let mover: TopBarMover
    let lift: CGFloat
    let content: Content

    func makeUIViewController(context: Context) -> TopBarController<Content> {
        let controller = TopBarController(content: content)
        mover.view = controller.host.view
        mover.lift = lift
        UIView.performWithoutAnimation { mover.move(away: mover.isAway) }
        return controller
    }

    func updateUIViewController(_ controller: TopBarController<Content>, context: Context) {
        controller.host.rootView = content
        mover.lift = lift
    }
}

final class TopBarController<Content: View>: UIViewController {
    let host: UIHostingController<Content>

    init(content: Content) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = TopBarView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Put where SwiftUI puts this, which allowed for the safe area already.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Takes touches only on the bar's own controls, the dots' capsule in the middle and the "…"
/// button at the end, on an iPad the Aa button at the start too, and in the share extension its
/// buttons at either end. Elsewhere along it they go to the page behind, as they did with the bar
/// in SwiftUI.
private final class TopBarView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        #if !SHARE_EXTENSION
        // An iPad's Aa and "…", where their toolbars have them. Left out, Aa took no touches:
        // they went to the page under it (user, 2026-10-08). In a window that isn't full screen,
        // Aa stands well along from its own place, past the window's controls, and it took none
        // there (2026-10-09).
        for button in barButtons(in: self) {
            if let round = button.buttonFrame(in: self), round.contains(point) {
                return button.buttonView(at: convert(point, to: button), with: event)
            }
        }
        #endif
        let height = DotSwitcher.height
        let capsule = CGRect(x: bounds.midX - DotSwitcher.width / 2, y: 0, width: DotSwitcher.width, height: height)
        let menu = CGRect(x: bounds.maxX - height, y: 0, width: height, height: height)
        #if SHARE_EXTENSION
        let start = CGRect(x: 0, y: 0, width: height, height: height)
        #else
        let start = CGRect.null
        #endif
        guard capsule.contains(point) || menu.contains(point) || start.contains(point) else { return nil }
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    #if !SHARE_EXTENSION
    private func barButtons(in view: UIView) -> [SystemBarButtonView] {
        view.subviews.flatMap { subview in
            (subview as? SystemBarButtonView).map { [$0] } ?? barButtons(in: subview)
        }
    }
    #endif
}

/// Draws the dots down the status bar's column in to the page's own dot as the keys come up over
/// the "…" button, and brings Aa and the button up under it, and back as the keys go (see
/// `SideColumn`): in the keys' own animation, which carries the change, as `TopBarMover` moves the
/// dot bar. By SwiftUI it would lag the keys.
@MainActor
final class ColumnMover {
    fileprivate weak var arranger: ColumnArranging?
    /// The column, and the screen's height, as last laid out.
    fileprivate var column: SideColumn?
    fileprivate var height: CGFloat = 0
    /// How tall the keys stand over the screen's foot.
    private(set) var keys: CGFloat = 0
    /// Set once UIKit says the keys are going, till they come back up: the dots open out then,
    /// with them. Left till the keys were down past the "…" button, they opened out late after
    /// keys a finger dragged away, which go only gradually.
    private var keysAreGoing = false

    /// How tall the keys have stood since they were last gone: on-screen keys stand well over 120
    /// points, a hardware keyboard's strip less (see `PagerContainerView`). On-screen keys going
    /// down pass through a strip's height, and the dots drew in again for a moment.
    private var tallestKeys: CGFloat = 0
    /// Whether the keys type into this window: of Bite's two side by side on iPhone Duo's inner
    /// screen, the keys up over both, the other's dots stay as they are, under the keys, as the
    /// system leaves the bars of a window not typed in; and so do Bite's beside another app typed
    /// in (see `PageWindows.hasKeys`).
    var holdsKeys: @MainActor () -> Bool = { true }
    /// Whether the dots were drawn in when last arranged.
    private var wasDrawnIn = false
    /// Called as the column changes, the status bar grown for a Live Activity or back: the pager
    /// brings the format bar up on the keys or takes it away (see `SideColumn.formatsOnKeys`).
    var onColumnChange: (() -> Void)?

    /// Whether the dots are drawn in: the keys are up over them, and staying.
    var isDrawnIn: Bool {
        !keysAreGoing && column?.drawsIn(keys: keys, height: height, onScreen: tallestKeys > 120) == true && holdsKeys()
    }

    /// Called inside the keys' animation, which then carries the change, and on every step of a
    /// drag of them.
    func keysChanged(to keys: CGFloat) {
        if keys > self.keys { keysAreGoing = false }
        self.keys = keys
        tallestKeys = keys > 0 ? max(tallestKeys, keys) : 0
        arrangeIfChanged()
    }

    /// UIKit says the keys are going.
    func keysGoing() {
        keysAreGoing = true
        arrangeIfChanged()
    }

    /// The keys moved over to another of Bite's windows, or to another app, or came back.
    func keysMoved() {
        arrangeIfChanged()
    }

    private func arrangeIfChanged() {
        guard isDrawnIn != wasDrawnIn else { return }
        // Keys a finger drags, or that go only gradually, have no animation of their own to carry it.
        if UIView.inheritedAnimationDuration > 0 {
            arrange(byKeys: true)
        } else {
            UIView.animate(springDuration: Self.spring, bounce: 0) { self.arrange(byKeys: true) }
        }
    }

    /// The spring that carries the change when the keys bring none: as they go, UIKit tells first.
    static let spring: TimeInterval = 0.35

    /// `byKeys` when the keys coming or going bring the change; not for a turn or another page.
    fileprivate func arrange(byKeys: Bool = false) {
        wasDrawnIn = isDrawnIn
        arranger?.arrange(drawnIn: wasDrawnIn, keysOnScreen: tallestKeys > 120, byKeys: byKeys)
    }

    #if DEBUG
    func attachForTesting(_ arranger: ColumnArranging, column: SideColumn, height: CGFloat) {
        self.arranger = arranger
        self.column = column
        self.height = height
        arranger.column = column
        arrange()
    }
    #endif
}

/// What lays out the column's dots and "…" button, drawn in or not: by on-screen keys, or a
/// hardware keyboard's short strip; as the keys come or go, or at once.
@MainActor
protocol ColumnArranging: AnyObject {
    var column: SideColumn? { get set }
    func arrange(drawnIn: Bool, keysOnScreen: Bool, byKeys: Bool)
}

/// The dots and the "…" button down the status bar's column, in a view controller of their own,
/// which `ColumnMover` arranges, laid out over the whole column. The dots are in glass of UIKit's,
/// which draws in to a round button with the page's dot in it.
struct ColumnHost<Dots: View, Dot: View, Menu: View>: UIViewControllerRepresentable {
    let mover: ColumnMover
    let column: SideColumn
    /// The screen's height.
    let height: CGFloat
    let dots: Dots
    /// The page's dot, alone, for the dots drawn in, and which page it is.
    let dot: Dot
    let page: Int
    /// Whether the page's dot is in its colour: the page has something on it.
    let pageIsColoured: Bool
    let menu: Menu
    /// The page's colour, for Aa's glyph, as the "…" button's.
    let tint: Color
    #if !SHARE_EXTENSION
    /// The window it's in, of Bite's two side by side on iPhone Duo's inner screen.
    @Environment(PageWindow.self) private var window: PageWindow?
    #endif

    func makeUIViewController(context: Context) -> ColumnController<Dots, Dot, Menu> {
        let controller = ColumnController(dots: dots, dot: dot, menu: menu)
        controller.page = page
        controller.pageIsColoured = pageIsColoured
        controller.tint = UIColor(tint)
        #if !SHARE_EXTENSION
        controller.window = window
        #endif
        mover.arranger = controller
        UIView.performWithoutAnimation { lay(out: controller) }
        return controller
    }

    func updateUIViewController(_ controller: ColumnController<Dots, Dot, Menu>, context: Context) {
        controller.dotsHost.rootView = dots
        controller.dotHost.rootView = dot
        controller.menuHost.rootView = menu
        controller.tint = UIColor(tint)
        #if !SHARE_EXTENSION
        controller.window = window
        #endif
        if controller.pageIsColoured != pageIsColoured { controller.pageIsColoured = pageIsColoured }
        if controller.page != page {
            controller.page = page
            UIView.performWithoutAnimation { mover.arrange() }
        }
        lay(out: controller)
    }

    private func lay(out controller: ColumnController<Dots, Dot, Menu>) {
        guard mover.column != column || mover.height != height || controller.column != column else { return }
        // Folded part way, or opened flat, or the status bar grown for a Live Activity, or back, the
        // screen otherwise the same: the dots and buttons move off the fold or the status bar, or
        // back, in the keys' spring, no animation coming with the change.
        let eases = mover.height == height && mover.column.map { was in
            var was = was
            was.fold = column.fold
            was.cameraRoom = column.cameraRoom
            was.camera = column.camera
            return was == column
        } == true
        mover.column = column
        mover.height = height
        controller.column = column
        if eases {
            UIView.animate(springDuration: ColumnMover.spring, bounce: 0) { mover.arrange() }
        } else {
            mover.arrange()
        }
        mover.onColumnChange?()
    }
}

final class ColumnController<Dots: View, Dot: View, Menu: View>: UIViewController, ColumnArranging {
    let dotsHost: UIHostingController<Dots>
    let dotHost: UIHostingController<Dot>
    let menuHost: UIHostingController<Menu>
    /// Aa, between the page's dot and the "…" button while the keys are up, the two coming up out of
    /// the keys: an iPad's, a bar button of the system's own alone in a toolbar, the format panel
    /// growing out of it with no arrow as it does there (see `SystemBarButton`). Not in the share
    /// extension, which has no column.
    #if !SHARE_EXTENSION
    private let formatCoordinator = SystemBarButton.Coordinator(action: nil, menu: nil)
    private(set) lazy var formatButton = SystemBarButtonView(symbol: "textformat", title: String(localized: "Format"),
                                                             edge: .leading, coordinator: formatCoordinator)
    /// Whether Aa's toolbar has drawn it: only once the column's on screen, and not for a moment as
    /// iPhone Duo is folded or opened. The turning dot hands over to it once it has. Aa shows
    /// whether or not: kept out of sight till then, it stayed out of sight, as nothing drew it
    /// again once its toolbar had, the phone folded with the keys up (user, 2026-10-31).
    private var formatIsPlaced = false
    /// The window it's in, of Bite's two side by side on iPhone Duo's inner screen.
    weak var window: PageWindow?
    #endif
    /// The page's colour, for Aa's glyph.
    var tint: UIColor = .tintColor {
        didSet {
            #if !SHARE_EXTENSION
            if isViewLoaded { formatButton.item.tintColor = tint }
            #endif
            updateTurningDot()
        }
    }
    /// The dots' glass and Aa's, in a container of glass, which runs glass close together into one:
    /// opening out, the dots' glass takes Aa's back in. Aa's toolbar draws no glass of its own.
    private let container: UIVisualEffectView = {
        let effect = UIGlassContainerEffect()
        effect.spacing = 10
        return UIVisualEffectView(effect: effect)
    }()
    private let glass = ColumnController.makeGlass()
    private let formatGlass = ColumnController.makeGlass()
    /// What of the dots shows: within the glass, 3 points in from its edge, as near its edge as
    /// keeps the dots beside the page's out of sight, drawn in to a round button: 30 points from its
    /// middle, an 18-point dot reaches 21 points out, the glass 24. Cut 5 points in, the dots went
    /// well inside the glass's edge (user, 2026-10-20).
    private let dotsClip = UIView()
    private static var clipInset: CGFloat { 3 }
    var column: SideColumn?
    /// The page on screen, whose dot the dots draw in to.
    var page = 0 {
        didSet { updateTurningDot() }
    }
    private var isDrawnIn = false
    /// Whether the page's dot, drawn in on its side, has turned into Aa, or is turning into it.
    private var dotIsTurned = false
    /// Whether Aa itself shows on its side, having taken over from the turning dot.
    private var formatHasTurned = false
    /// The page's dot turning into Aa and back, on its side, in for the dots' own and Aa's
    /// toolbar's, which take over once it has turned (see `TurningDot`).
    private let turning = ColumnTurn()
    private lazy var turnHost = UIHostingController(rootView: turningDot)
    /// Whether the page's dot is in its colour: the page has something on it.
    var pageIsColoured = true {
        didSet { updateTurningDot() }
    }
    /// Watching for Aa's next step: upright, for the dots' glass, opening out, to reach Aa's; on its
    /// side, for the dots to have drawn in, to turn the page's dot into Aa, or for the time to open
    /// them out from it, turned back.
    private var formatWatcher: FrameWatcher?
    #if !SHARE_EXTENSION
    #endif

    init(dots: Dots, dot: Dot, menu: Menu) {
        dotsHost = UIHostingController(rootView: dots)
        dotHost = UIHostingController(rootView: dot)
        menuHost = UIHostingController(rootView: menu)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeGlass() -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glass = UIVisualEffectView(effect: effect)
        glass.cornerConfiguration = .capsule()
        return glass
    }

    /// How long Aa and the "…" button take to come up out of the keys, and when they set off: the
    /// keys are up over the button 0.035 s in, on iPhone Duo. Aa leaves from under the screen's
    /// foot 0.04 s in and comes out of the keys' top edge at 0.14 s; the button follows 0.06 s
    /// after and comes out at 0.21 s, under Aa, the two never meeting.
    private static var riseDuration: TimeInterval { 0.35 }
    private static var formatDelay: TimeInterval { 0.04 }
    private static var menuDelay: TimeInterval { 0.10 }
    /// When Aa parts from the page's dot, over a hardware keyboard's strip: as the dots finish
    /// drawing in, so it parts from a round of glass as big as itself.
    private static var partDelay: TimeInterval { 0.22 }
    /// On its side, how long the page's dot takes turning into Aa, and back as the keys go, briskly,
    /// the dots opening out from it once it's clear of its blur: sooner, it went sharp at once as
    /// the dots took over. It turns once the dots have drawn in to it, within `turnLeeway` points
    /// of a round: sooner, the dots beside it, not yet out of sight, went at once. Aa's toolbar
    /// takes over in `handOverDuration`, the two a hair apart at most, as it puts it on the
    /// screen's pixels its own way.
    private static var turnDuration: TimeInterval { 0.35 }
    private static var turnBackDuration: TimeInterval { 0.25 }
    private static var turnLeeway: CGFloat { 2 }
    private static var handOverDuration: TimeInterval { 0.1 }
    /// How long the dots take opening out from the page's dot, turned back, on their own, the keys
    /// gone ahead of them.
    private static var openDuration: TimeInterval { 0.35 }

    override func loadView() {
        let view = ColumnView()
        view.targets = { [weak self] in
            guard let self else { return [] }
            return [self.glass, self.menuHost.view]
        }
        #if !SHARE_EXTENSION
        view.format = { [weak self] in
            guard let self, self.isDrawnIn else { return nil }
            return self.formatButton
        }
        #endif
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        container.frame = view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        // Aa's under the dots', where it waits inside them, under the page's dot.
        container.contentView.addSubview(formatGlass)
        container.contentView.addSubview(glass)
        // The dots stay, the glass drawing in over them and opening out again.
        dotsClip.cornerConfiguration = .capsule()
        dotsClip.clipsToBounds = true
        glass.contentView.addSubview(dotsClip)
        for host in [dotsHost, dotHost] as [UIViewController] {
            addChild(host)
            dotsClip.addSubview(host.view)
        }
        #if !SHARE_EXTENSION
        formatCoordinator.action = { [weak self] item in self?.showFormat(from: item) }
        formatButton.item.tintColor = tint
        formatButton.item.hidesSharedBackground = true
        // In the middle of its glass however the screen's kept clear at its edge: the toolbar moved
        // it along, out of the column's own room, off the glass, and further on as iPhone Duo was
        // folded or opened (user, 2026-10-31). See `SystemBarButtonView.keepsClear`.
        formatButton.keepsClear = false
        formatGlass.contentView.addSubview(formatButton)
        // A touch on the dots or the buttons says this is the window in use, as one on its pages
        // does: the keys go to the page being typed in here, if they're up.
        view.addGestureRecognizer(UseRecognizer(onLift: true) { [weak self] in
            guard let pager = self?.window?.pager else { return }
            PageWindows.shared.pagerWasUsed(pager)
        })
        #endif
        addChild(turnHost)
        glass.contentView.addSubview(turnHost.view)
        turnHost.view.alpha = 0
        turnHost.view.isUserInteractionEnabled = false
        // Aa's and the dots' own speak for it.
        turnHost.view.accessibilityElementsHidden = true
        addChild(menuHost)
        view.addSubview(menuHost.view)
        for host in [dotsHost, dotHost, turnHost, menuHost] as [UIViewController] {
            host.view.backgroundColor = .clear
            host.didMove(toParent: self)
        }
        // Put where this puts them, which allowed for the safe area already.
        dotsHost.safeAreaRegions = []
        dotHost.safeAreaRegions = []
        turnHost.safeAreaRegions = []
        menuHost.safeAreaRegions = []
        UIView.performWithoutAnimation { arrange(drawnIn: isDrawnIn, keysOnScreen: true, byKeys: false) }
    }

    /// The dots in their capsule, midway down the column, and the button at its foot; or, drawn
    /// in, the page's dot in a round button under the status bar, Aa under it and the "…" button
    /// under that; on its side, Aa where the page's dot was.
    func arrange(drawnIn: Bool, keysOnScreen: Bool, byKeys: Bool) {
        isDrawnIn = drawnIn
        formatWatcher?.stop()
        guard isViewLoaded, let column else { return }
        let animated = UIView.inheritedAnimationDuration > 0
        #if !SHARE_EXTENSION
        placeFormat()
        #endif
        let clearsOut = drawnIn && keysOnScreen && column.formatsOnKeys
        if clearsOut {
            clearOut(column)
        } else if column.isShort {
            arrangeOnItsSide(column, byKeys: byKeys && animated)
        } else {
            arrangeUpright(column, keysOnScreen: keysOnScreen, byKeys: byKeys, animated: animated)
        }
        // Out of sight under the keys, nothing of it to read.
        menuHost.view.accessibilityElementsHidden = clearsOut
    }

    /// With the format bar on the keys, as under a status bar grown for a Live Activity (see
    /// `SideColumn.formatsOnKeys`), the dots, Aa and the "…" button go down under the keys as they
    /// come up, out of sight, and come back up out of them as they go, as the dot bar goes up out
    /// of their way and back on a phone on its side.
    private func clearOut(_ column: SideColumn) {
        let left = column.frame.minX
        let below = column.frame.height + 10
        UIView.performWithoutAnimation {
            dotsHost.view.alpha = 1
            turnHost.view.alpha = 0
        }
        dotIsTurned = false
        formatHasTurned = false
        turnAtOnce(intoFormat: false)
        // As they stand, at rest or drawn in to the page's dot: drawing in or opening out on the way
        // down, the dots beside the page's showed.
        placeDots(column, drawnIn: glass.frame.height < DotSwitcher.width)
        glass.frame.origin.y = below
        dotsHost.view.accessibilityElementsHidden = true
        dotHost.view.alpha = 0
        dotHost.view.accessibilityElementsHidden = true
        formatGlass.frame = underFoot(column)
        menuHost.view.frame = CGRect(x: column.button.minX - left, y: below, width: SideColumn.glass, height: SideColumn.glass)
        #if !SHARE_EXTENSION
        formatButton.accessibilityElementsHidden = true
        #endif
    }

    /// Upright, drawn in, the page's dot is a button under the status bar. Aa comes up from under
    /// the screen's foot, behind the keys, once they're up over the "…" button, and out of their top
    /// edge ahead of the button, which follows it out and stops under it (user, 2026-10-20). Parted
    /// from the page's dot, Aa came from nowhere near the keys. A hardware keyboard's strip is too
    /// short to hide them behind: over it Aa's glass draws in under the page's dot, with the dots,
    /// and parts from it once they have. Opening out, the dots' glass takes Aa's back in under the
    /// page's dot, and the button goes back ahead of the keys.
    private func arrangeUpright(_ column: SideColumn, keysOnScreen: Bool, byKeys: Bool, animated: Bool) {
        let drawnIn = isDrawnIn
        let left = column.frame.minX
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -left, dy: 0) }
        // Whatever it was on its side.
        UIView.performWithoutAnimation {
            dotsHost.view.alpha = 1
            turnHost.view.alpha = 0
        }
        dotIsTurned = false
        formatHasTurned = false
        turnAtOnce(intoFormat: false)
        // Out from under the keys, where the column cleared out to for the format bar (see
        // `clearOut`): the dots come back up as they're to stand, drawn in to the page's dot with
        // the keys staying up as the Live Activity goes, Aa and the button coming up after it as
        // out of the keys. Coming up all at once, the dots drawing in on the way, the three ran
        // together.
        let returns = animated && glass.frame.minY >= column.frame.height
        if returns {
            UIView.performWithoutAnimation {
                placeDots(column, drawnIn: drawnIn)
                glass.frame.origin.y = column.frame.height + 10
            }
        }
        placeDots(column, drawnIn: drawnIn)
        dotHost.view.alpha = drawnIn ? 1 : 0
        dotHost.view.accessibilityElementsHidden = !drawnIn
        let underRestingDot = underRestingDot(column)
        let underDot = drawnIn ? local(column.typingDot) : underRestingDot
        let slot = local(column.typingFormat)
        let underFoot = underFoot(column)
        let menuFrame = local(drawnIn ? column.typingMenu : column.button)
        let entering = drawnIn && animated && (byKeys || returns)
        let parts = entering && !keysOnScreen
        if entering && !parts {
            UIView.performWithoutAnimation { formatGlass.frame = underFoot }
            rise(formatGlass, to: slot, after: Self.formatDelay)
            rise(menuHost.view, to: menuFrame, after: Self.menuDelay)
        } else if parts {
            UIView.performWithoutAnimation { formatGlass.frame = underRestingDot }
            formatGlass.frame = underDot
            rise(formatGlass, to: slot, after: Self.partDelay)
            menuHost.view.frame = menuFrame
        } else {
            formatGlass.frame = drawnIn ? slot : animated && byKeys ? underDot : underFoot
            menuHost.view.frame = menuFrame
        }
        #if !SHARE_EXTENSION
        let shows = drawnIn
        if parts && shows {
            // As its glass comes clear of the page's dot.
            UIView.animate(withDuration: 0.18, delay: Self.partDelay + 0.06,
                           options: [.overrideInheritedDuration, .overrideInheritedCurve, .curveEaseOut]) {
                self.formatButton.alpha = 1
            }
        } else if animated && byKeys && !drawnIn {
            // Gone the moment the dots' glass reaches Aa's, as seen frame by frame, before the dots
            // coming out under it reach Aa: gone at once, its glass stood empty a moment; faded, or
            // gone at a time worked out ahead, it showed over the dots, the keys' own curve far
            // quicker at first than any guess of it.
            watchForMeeting()
        } else {
            UIView.performWithoutAnimation { formatButton.alpha = shows ? 1 : 0 }
        }
        formatButton.accessibilityElementsHidden = !drawnIn
        #endif
    }

    /// On its side the keys leave the column room for two buttons only: the dots draw in to the
    /// page's dot as upright, the first thing to go, and it turns into Aa where it is, one glass
    /// all the while, the "…" button coming up out of the keys under it, or staying over it at the
    /// top; as the keys go, Aa turns back into the page's dot and the dots open out from it (user,
    /// 2026-10-20). Aa came up out of the keys to cover the page's dot before: the two glasses ran
    /// together into shapes the system never shows, and the dots had to be cut where it was.
    private func arrangeOnItsSide(_ column: SideColumn, byKeys: Bool) {
        let drawnIn = isDrawnIn
        let left = column.frame.minX
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -left, dy: 0) }
        dotHost.view.alpha = 0
        dotHost.view.accessibilityElementsHidden = true
        #if !SHARE_EXTENSION
        formatButton.accessibilityElementsHidden = !drawnIn
        #endif
        let slot = local(column.typingFormat)
        let menuFrame = local(drawnIn ? column.typingMenu : column.button)
        guard byKeys else {
            placeDots(column, drawnIn: drawnIn)
            formatGlass.frame = drawnIn ? slot : underFoot(column)
            menuHost.view.frame = menuFrame
            if drawnIn && !formatHasTurned {
                // Turning, or about to, as the keys came up: carry on.
                if !dotIsTurned { watchForDrawingIn() }
            } else {
                UIView.performWithoutAnimation { showTurned(drawnIn) }
            }
            return
        }
        if drawnIn {
            // Aa's glass inside the dots' as they draw in, to turn up where the page's dot was.
            let isResting = glass.frame == local(column.dots) && (glass.layer.animationKeys() ?? []).isEmpty
            if isResting {
                UIView.performWithoutAnimation { formatGlass.frame = underRestingDot(column) }
            }
            placeDots(column, drawnIn: true)
            formatGlass.frame = slot
            rise(menuHost.view, to: menuFrame, after: Self.menuDelay)
            if !dotIsTurned { watchForDrawingIn() }
        } else {
            menuHost.view.frame = menuFrame
            if dotIsTurned {
                turn(intoFormat: false) { [weak self] in self?.openOut(column) }
            } else {
                // Not turned yet: open out with the keys.
                placeDots(column, drawnIn: false)
                formatGlass.frame = underRestingDot(column)
            }
        }
    }

    /// The dots' glass round the dots, or drawn in to the page's dot, which goes from its place
    /// among them to the middle of the round, the dots with it, the glass drawing in over the
    /// others; and back.
    private func placeDots(_ column: SideColumn, drawnIn: Bool) {
        let glassFrame = (drawnIn ? column.typingDot : column.dots).offsetBy(dx: -column.frame.minX, dy: 0)
        glass.frame = glassFrame
        let middle = glassFrame.height / 2
        let inset = Self.clipInset
        dotsClip.frame = CGRect(origin: .zero, size: glassFrame.size).insetBy(dx: inset, dy: inset)
        dotsHost.view.bounds = CGRect(x: 0, y: 0, width: SideColumn.glass, height: DotSwitcher.width)
        dotsHost.view.center = CGPoint(x: glassFrame.width / 2 - inset,
                                       y: (drawnIn ? middle - (Self.pageDot(page) - DotSwitcher.width / 2) : middle) - inset)
        dotsHost.view.accessibilityElementsHidden = drawnIn
        dotHost.view.bounds = CGRect(x: 0, y: 0, width: SideColumn.glass, height: SideColumn.glass)
        dotHost.view.center = CGPoint(x: glassFrame.width / 2 - inset, y: middle - inset)
        turnHost.view.bounds = CGRect(x: 0, y: 0, width: SideColumn.glass, height: SideColumn.glass)
        turnHost.view.center = CGPoint(x: glassFrame.width / 2, y: middle)
    }

    /// How far down the dots the page's dot's middle is.
    private static func pageDot(_ page: Int) -> CGFloat {
        let pitch = (DotSwitcher.width - 16) / CGFloat(DotPalette.count)
        return 8 + (CGFloat(page) + 0.5) * pitch
    }

    /// Aa's glass under the page's dot among the dots at rest, inside theirs.
    private func underRestingDot(_ column: SideColumn) -> CGRect {
        let half = SideColumn.glass / 2
        let dotMiddle = min(max(Self.pageDot(page), half), DotSwitcher.width - half)
        let dots = column.dots.offsetBy(dx: -column.frame.minX, dy: 0)
        return CGRect(x: dots.minX, y: dots.minY + dotMiddle - half, width: SideColumn.glass, height: SideColumn.glass)
    }

    /// Aa's glass out of sight, under the screen's foot, under where it comes up to.
    private func underFoot(_ column: SideColumn) -> CGRect {
        let slot = column.typingFormat.offsetBy(dx: -column.frame.minX, dy: 0)
        return slot.offsetBy(dx: 0, dy: column.frame.height + 10 - slot.minY)
    }

    /// The page's dot, or Aa in its place, at once.
    private func showTurned(_ turned: Bool) {
        dotIsTurned = turned
        formatHasTurned = turned
        dotsHost.view.alpha = turned ? 0 : 1
        turnHost.view.alpha = 0
        turnAtOnce(intoFormat: turned)
        #if !SHARE_EXTENSION
        formatButton.alpha = turned ? 1 : 0
        #endif
    }

    /// Turns the page's dot into Aa once the dots have drawn in to it.
    private func watchForDrawingIn() {
        let started = CACurrentMediaTime()
        formatWatcher = FrameWatcher { [weak self] in
            guard let self else { return true }
            let dots = glass.layer.presentation()?.frame ?? glass.frame
            guard dots.height <= SideColumn.glass + Self.turnLeeway || CACurrentMediaTime() - started > 1 else { return false }
            turn(intoFormat: true)
            return true
        }
    }

    /// Turns the page's dot, drawn in on its side, into Aa, or Aa back into the dot, as the system
    /// replaces one symbol with another: the one blurring away smaller as the other comes out of the
    /// blur from smaller (`TurningDot`). Drawn one over the other, fading and scaling, they looked
    /// laid on each other (user, 2026-10-21). The turning dot takes over from the dots' own page's
    /// dot and Aa's toolbar, the same to the pixel, and hands back to them once it has turned, then
    /// `then`.
    private func turn(intoFormat: Bool, then: (() -> Void)? = nil) {
        dotIsTurned = intoFormat
        formatHasTurned = false
        UIView.performWithoutAnimation {
            #if !SHARE_EXTENSION
            if intoFormat { placeFormat() }
            formatButton.alpha = 0
            #endif
            dotsHost.view.alpha = 0
            turnHost.view.alpha = 1
        }
        withAnimation(.smooth(duration: intoFormat ? Self.turnDuration : Self.turnBackDuration)) {
            turning.showsFormat = intoFormat
        } completion: { [weak self] in
            guard let self, dotIsTurned == intoFormat, isDrawnIn == intoFormat else { return }
            if intoFormat {
                formatHasTurned = true
                #if !SHARE_EXTENSION
                // Aa there under it at once, and the turning dot fading off it: the two fading
                // over each other, Aa went paler a moment.
                UIView.performWithoutAnimation { self.formatButton.alpha = 1 }
                UIView.animate(withDuration: Self.handOverDuration) { self.turnHost.view.alpha = 0 }
                #endif
            } else {
                UIView.performWithoutAnimation {
                    self.dotsHost.view.alpha = 1
                    self.turnHost.view.alpha = 0
                }
                then?()
            }
        }
    }

    /// The turning dot showing the page's dot, or Aa, at once, out of sight.
    private func turnAtOnce(intoFormat: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { turning.showsFormat = intoFormat }
    }

    /// Opens the dots out from the page's dot, turned back, on their own, Aa's glass with them
    /// inside theirs.
    private func openOut(_ column: SideColumn) {
        UIView.animate(springDuration: Self.openDuration, bounce: 0) {
            self.placeDots(column, drawnIn: false)
            self.formatGlass.frame = self.underRestingDot(column)
        }
    }

    private var turningDot: TurningDot {
        TurningDot(turn: turning, ink: DotPalette.colors[page], isColoured: pageIsColoured, tint: Color(uiColor: tint))
    }

    private func updateTurningDot() {
        guard isViewLoaded else { return }
        turnHost.rootView = turningDot
    }

    #if !SHARE_EXTENSION
    /// Hides Aa the moment the dots' glass, opening out, touches Aa's, going in under it.
    private func watchForMeeting() {
        let started = CACurrentMediaTime()
        formatWatcher = FrameWatcher { [weak self] in
            guard let self else { return true }
            let format = formatGlass.layer.presentation()?.frame ?? formatGlass.frame
            let dots = glass.layer.presentation()?.frame ?? glass.frame
            guard max(dots.minY - format.maxY, format.minY - dots.maxY) <= 0 || CACurrentMediaTime() - started > 1 else { return false }
            UIView.performWithoutAnimation { self.formatButton.alpha = 0 }
            return true
        }
    }

    #endif

    /// Moves `view` to `frame` in a spring of its own, `delay` into the keys' animation.
    private func rise(_ view: UIView, to frame: CGRect, after delay: TimeInterval) {
        UIView.animate(springDuration: Self.riseDuration, bounce: 0, initialSpringVelocity: 0, delay: delay,
                       options: [.overrideInheritedDuration, .overrideInheritedCurve]) {
            view.frame = frame
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeFormatIfNeeded()
    }


    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        placeFormatIfNeeded()
    }

    #if !SHARE_EXTENSION
    /// Puts Aa on its glass, noting whether its toolbar has drawn it yet.
    private func placeFormat() {
        formatIsPlaced = place(formatButton, at: CGRect(x: 0, y: 0, width: SideColumn.glass, height: SideColumn.glass))
    }

    /// Puts the button's round on `slot`, in the middle of its view, where its toolbar draws it,
    /// keeping nothing clear. False while the toolbar can't tell where it draws it. Moved by where
    /// the toolbar said it drew it, Aa went off its glass as iPhone Duo was folded, opened or
    /// turned: midway through, the toolbar told of where it had drawn it before (user, 2026-10-31).
    private func place(_ button: SystemBarButtonView, at slot: CGRect) -> Bool {
        button.bounds = CGRect(origin: .zero, size: slot.size)
        button.layoutIfNeeded()
        button.center = CGPoint(x: slot.midX, y: slot.midY)
        return button.buttonFrame(in: button) != nil
    }
    #endif

    private func placeFormatIfNeeded() {
        #if !SHARE_EXTENSION
        guard !formatIsPlaced, let column else { return }
        UIView.performWithoutAnimation {
            placeFormat()
            guard formatIsPlaced else { return }
            if column.isShort {
                // Not before the turning dot has turned into it.
                formatButton.alpha = formatHasTurned ? 1 : 0
                if formatHasTurned { turnHost.view.alpha = 0 }
            } else {
                formatButton.alpha = isDrawnIn ? 1 : 0
            }
        }
        #endif
    }

    #if !SHARE_EXTENSION

    /// The format panel, out of Aa, as an iPad's opens it: on iPhone Duo's inner screen as big as an
    /// iPad's, on its outer one smaller, as the system's own is there.
    private func showFormat(from item: UIBarButtonItem) {
        let isBig = SideColumn.isBigScreen(traitCollection)
        FormatPanel.shared.show(from: item, in: view.window, metrics: isBig ? .regular : .compact)
    }
    #endif

    #if DEBUG
    var glassFrameForTesting: CGRect { glass.frame }
    var menuFrameForTesting: CGRect { menuHost.view.frame }
    var glassIsMovingForTesting: Bool { !(glass.layer.animationKeys() ?? []).isEmpty }
    var formatFrameForTesting: CGRect { formatGlass.frame }
    var formatIsMovingForTesting: Bool { !(formatGlass.layer.animationKeys() ?? []).isEmpty }
    var menuIsMovingForTesting: Bool { !(menuHost.view.layer.animationKeys() ?? []).isEmpty }
    #endif
}

/// Whether the column's turning dot shows Aa, on its side, or the page's dot.
@MainActor @Observable
final class ColumnTurn {
    var showsFormat = false
}

/// The page's dot drawn in on its side, and Aa that it turns into and back from, as the system
/// replaces one symbol with another: the dot as the dot bar draws it, Aa as its toolbar draws it,
/// its image a size larger.
struct TurningDot: View {
    let turn: ColumnTurn
    let ink: DotColor
    /// Whether the page's dot is in its colour: the page has something on it.
    let isColoured: Bool
    let tint: Color
    /// Whether the page on screen's dot glows, as chosen in Settings.
    @State private var dotGlows = Preferences.dotGlows

    var body: some View {
        ZStack {
            if turn.showsFormat {
                Image(systemName: "textformat")
                    .font(.system(size: 17, weight: .semibold))
                    .imageScale(.large)
                    .foregroundStyle(tint)
                    .transition(.blurReplace)
            } else {
                // An empty page's grey isn't lit, as in the dot bar.
                DotIndicator(ink: isColoured ? ink : DotPalette.empty, isSelected: true, glows: dotGlows && isColoured)
                    .transition(.blurReplace)
            }
        }
        .frame(width: SideColumn.glass, height: SideColumn.glass)
        .onReceive(NotificationCenter.default.publisher(for: Preferences.didChange)) { _ in
            dotGlows = Preferences.dotGlows
        }
    }
}

/// Calls `tick` on every frame the screen draws till it says it's done, or till stopped.
private final class FrameWatcher: NSObject {
    private var link: CADisplayLink?
    private let tick: () -> Bool

    init(tick: @escaping () -> Bool) {
        self.tick = tick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step() {
        if tick() { stop() }
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

/// Takes touches only on the dots, or the page's dot they draw in to, Aa while it shows, and the
/// "…" button; elsewhere down the column they go to the page behind.
private final class ColumnView: UIView {
    var targets: () -> [UIView] = { [] }
    #if !SHARE_EXTENSION
    /// Aa while it shows, which its toolbar draws where it likes (see `SystemBarButtonView`).
    var format: () -> SystemBarButtonView? = { nil }
    #endif

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        #if !SHARE_EXTENSION
        if let button = format(), let round = button.buttonFrame(in: self), round.contains(point) {
            return button.buttonView(at: convert(point, to: button), with: event)
        }
        #endif
        guard targets().contains(where: { $0.frame.contains(point) }) else { return nil }
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}
