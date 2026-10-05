import SwiftUI
import UIKit
import BiteKit

/// The seven editors side by side in a paging scroll view.
///
/// This replaces a page-style `TabView`, which creates pages lazily and can be scrolled by
/// UIKit on its own. Here pages only move when you swipe or tap a dot, and the keyboard
/// follows you to the new page.
struct DotPager: UIViewRepresentable {
    @Binding var selection: Int
    /// The page mostly on screen right now. During a swipe it runs ahead of or behind
    /// `selection`, and the dot bar follows it.
    @Binding var visiblePage: Int
    /// Set while a finger is on the dot bar.
    var isDotBarTouched = false
    /// Set while the dot bar is up out of the way of the keys, on a phone on its side.
    @Binding var isTopBarAway: Bool
    @Environment(DotStore.self) private var store

    func makeCoordinator() -> DotPagerCoordinator {
        DotPagerCoordinator()
    }

    func makeUIView(context: Context) -> PagerContainerView {
        let coordinator = context.coordinator
        let store = store
        for controller in coordinator.controllers {
            let dot = controller.dot
            controller.onChange = { markdown in
                store.update(dot: dot, markdown: markdown)
            }
            controller.onEmptyChange = { isEmpty in
                store.update(dot: dot, isEmpty: isEmpty)
            }
            controller.load(markdown: store.markdown[dot])
            controller.loadedRevision = store.revisions[dot]
        }
        store.reportPendingEdits = { [weak coordinator] in
            coordinator?.controllers.forEach { $0.reportPendingChange() }
        }
        store.applyInEditor = { [weak coordinator] dot, markdown in
            coordinator?.controllers[dot].applyRemote(markdown: markdown)
        }
        store.clearInEditor = { [weak coordinator] dot in
            coordinator?.controllers[dot].clear()
        }
        coordinator.scrollView.currentPage = selection
        coordinator.letPageScrollToTop(selection)
        return coordinator.container
    }

    func updateUIView(_ container: PagerContainerView, context: Context) {
        let coordinator = context.coordinator
        let binding = $selection
        coordinator.select = { binding.wrappedValue = $0 }
        let visible = $visiblePage
        coordinator.showVisiblePage = { page in
            if visible.wrappedValue != page { visible.wrappedValue = page }
        }
        let away = $isTopBarAway
        coordinator.showTopBarAway = { isAway, animation in
            // Told from inside the pager's layout, which SwiftUI may be running.
            DispatchQueue.main.async {
                withAnimation(animation) { away.wrappedValue = isAway }
            }
        }
        for controller in coordinator.controllers where controller.loadedRevision != store.revisions[controller.dot] {
            controller.loadedRevision = store.revisions[controller.dot]
            controller.load(markdown: store.markdown[controller.dot])
        }
        // Before the page: the finger that picked it may still be down.
        coordinator.isDotBarTouched = isDotBarTouched
        coordinator.show(page: selection)
    }
}

final class DotPagerCoordinator: NSObject, UIScrollViewDelegate {
    let controllers = DotPalette.colors.indices.map { EditorController(dot: $0, accent: DotPalette.colors[$0].platformColor) }
    let container = PagerContainerView()
    var scrollView: PagerScrollView { container.scrollView }
    var select: ((Int) -> Void)?
    var showVisiblePage: ((Int) -> Void)?
    var showTopBarAway: ((Bool, Animation?) -> Void)?
    /// One tick each time the dot bar moves to another dot, including every dot passed on the
    /// way when jumping several pages.
    private let haptics = UISelectionFeedbackGenerator()
    private var lastVisiblePage: Int?
    /// Set while a swipe settles, so the keyboard moves over once it lands.
    private var pageAwaitingFocus: Int?
    /// Set while the keyboard waits to move over until the pager is let go of.
    private var isWaitingToPassKeyboard = false

    override init() {
        super.init()
        scrollView.delegate = self
        scrollView.scrollsToTop = false
        scrollView.pageViews = controllers.map(\.textView)
        container.onKeyboardOverlapChange = { [weak self] overlap in
            guard let self else { return }
            let isComingUp = overlap > 0 && self.controllers.first?.textView.keyboardOverlap == 0
            self.controllers.forEach { $0.textView.keyboardOverlap = overlap }
            // Once the keys are up; readying pages while they slide in could hold them up.
            if isComingUp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self else { return }
                    self.prepareNeighbors(of: self.scrollView.currentPage)
                }
            }
        }
        container.onTopBarAwayChange = { [weak self] isAway, animation in
            guard let self else { return }
            self.controllers.forEach { $0.textView.isTopBarAway = isAway }
            self.showTopBarAway?(isAway, animation)
        }
        container.editingTextView = { [weak self] in
            if let page = self?.controllers.first(where: { $0.textView.isFirstResponder }) { return page.textView }
            // The keys moved over to a link on the page, in the format bar.
            let bar = FormatBar.shared
            return bar.isEditingLink ? bar.editor?.textView : nil
        }
        for controller in controllers {
            controller.onWritingToolsChange = { [weak self] isAtWork in
                self?.container.isWritingToolsAtWork = isAtWork
            }
            controller.onBeginEditing = { [weak self] in
                self?.container.pageTookKeys()
            }
            controller.onEditLink = { [weak self, weak controller] link in
                guard let self, let controller else { return }
                self.container.editLinkOnKeys(link, of: controller)
            }
            controller.canEditLinkInBar = { [weak self, weak controller] in
                guard let self, let controller else { return false }
                return self.container.canEditLinks(on: controller)
            }
        }
    }

    /// Tapping the status bar scrolls to the top only when a single scroll view on screen asks
    /// for it, so only the page on screen does: not the pager, nor the pages beside it.
    func letPageScrollToTop(_ page: Int) {
        for controller in controllers {
            controller.textView.scrollsToTop = controller.dot == page
        }
    }

    /// Whether a page has the keys, or they've moved over to a link on it, in the format bar.
    private var keyboardIsUp: Bool {
        controllers.contains { $0.textView.isFirstResponder } || FormatBar.shared.isEditingLink
    }

    /// Set while SwiftUI is updating the pager, when its state can't change.
    private var isInSwiftUIUpdate = false

    /// Set while a finger is on the dot bar. Sliding along it passes page after page, and the
    /// keyboard waits for the finger to lift: passed on at every dot, it held each one up.
    var isDotBarTouched = false {
        didSet {
            if oldValue, !isDotBarTouched { dotBarLetGo() }
        }
    }

    /// Selection changed from SwiftUI (the dot bar).
    func show(page: Int) {
        guard page != scrollView.currentPage, controllers.indices.contains(page) else { return }
        // Picked during a swipe, this page takes the keyboard, not the one the swipe was headed for.
        pageAwaitingFocus = nil
        let moveKeyboard = keyboardIsUp
        // The page shows up already where it will be edited, not scrolling there once it has.
        if moveKeyboard, !controllers[page].textView.isFirstResponder { controllers[page].arrive() }
        haptics.prepare()
        isInSwiftUIUpdate = true
        scrollView.go(to: page)
        isInSwiftUIUpdate = false
        if moveKeyboard, !isDotBarTouched {
            passKeyboard(to: page)
        }
    }

    /// The finger is off the dot bar, and the page it left on screen takes the keyboard.
    private func dotBarLetGo() {
        let page = scrollView.currentPage
        guard keyboardIsUp, !controllers[page].textView.isFirstResponder else { return }
        passKeyboard(to: page)
    }

    /// Hands the keyboard to `page`. The page giving it up keeps its room for the keyboard, as
    /// it's likely swiped back to, and the pages beside the new one are readied.
    private func passKeyboard(to page: Int) {
        controllers.first { $0.textView.isFirstResponder && $0.dot != page }?.textView.keepKeyboardRoom()
        controllers[page].focus()
        prepareNeighbors(of: page)
    }

    /// With the keyboard up, a page is made ready to be swiped to while it's still off screen
    /// (see `EditorController.arrive`).
    private func ready(_ page: Int) {
        guard keyboardIsUp, controllers.indices.contains(page), !controllers[page].textView.isFirstResponder else { return }
        controllers[page].arrive()
    }

    /// The pages beside `page`, readied once the current frame is done, while nothing moves. A
    /// page can take several milliseconds, more than a frame, and done as a finger started to
    /// drag, it made the page catch. The pages further away follow, one at a time.
    private func prepareNeighbors(of page: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.scrollView.isDragging, !self.scrollView.isDecelerating else { return }
            self.ready(page - 1)
            self.ready(page + 1)
            self.prepareFarPages(from: page)
        }
    }

    /// Readies the nearest page to `page` that isn't ready yet, a moment later, and then the next,
    /// while the keyboard stays on `page`. A finger sliding along the dots then finds every page
    /// ready; readying them as it went held up each dot it passed, the first time.
    private func prepareFarPages(from page: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.keyboardIsUp, self.scrollView.currentPage == page,
                  self.controllers[page].textView.isFirstResponder else { return }
            let waiting = self.controllers.indices.filter { !self.controllers[$0].textView.keepsKeyboardRoom && $0 != page }
            guard let next = waiting.min(by: { abs($0 - page) < abs($1 - page) }) else { return }
            // While anything moves, the page being scrolled too, it waits its turn.
            if self.isStill(showing: page), !self.isDotBarTouched {
                self.ready(next)
            }
            self.prepareFarPages(from: page)
        }
    }

    /// The page a drag heads for: to the right for a finger moving left.
    private func pageAhead(of page: Int, in scrollView: UIScrollView) -> Int? {
        let pan = scrollView.panGestureRecognizer
        let moved = pan.translation(in: scrollView).x
        let heading = moved != 0 ? moved : pan.velocity(in: scrollView).x
        guard heading != 0 else { return nil }
        return page + (heading < 0 ? 1 : -1)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let page = min(max(Int((scrollView.contentOffset.x / width).rounded()), 0), controllers.count - 1)
        guard page != lastVisiblePage else { return }
        // The first position is where the pager starts, not a change.
        if lastVisiblePage != nil, Preferences.playsHaptics {
            haptics.selectionChanged()
        }
        lastVisiblePage = page
        letPageScrollToTop(page)
        // A drag carried on past the next page brings the one after it on screen.
        if scrollView.isDragging, let ahead = pageAhead(of: page, in: scrollView) {
            DispatchQueue.main.async { [weak self] in self?.ready(ahead) }
        }
        if isInSwiftUIUpdate {
            // The jump from the dot bar lands in the middle of SwiftUI's update, which would drop
            // the change; pass it on right after.
            DispatchQueue.main.async { [weak self] in self?.showVisiblePage?(page) }
        } else {
            showVisiblePage?(page)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        haptics.prepare()
        // Only the page the drag heads for, and only if it isn't ready yet. Pulled past the first
        // or last page there's none: readying the page behind made the rubber band catch.
        if let ahead = pageAhead(of: self.scrollView.currentPage, in: scrollView),
           controllers.indices.contains(ahead), !controllers[ahead].textView.keepsKeyboardRoom {
            ready(ahead)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishSwipe() }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let width = max(scrollView.bounds.width, 1)
        let page = min(max(Int((targetContentOffset.pointee.x / width).rounded()), 0), controllers.count - 1)
        guard page != self.scrollView.currentPage else { return }
        if keyboardIsUp {
            pageAwaitingFocus = page
            // Flicked on again before this lands, the next page would be readied as the finger
            // comes down. Now, as the page flies, it's done by then.
            let beyond = page + (page > self.scrollView.currentPage ? 1 : -1)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.controllers.indices.contains(beyond),
                      !self.controllers[beyond].textView.keepsKeyboardRoom else { return }
                self.ready(beyond)
            }
        }
        self.scrollView.currentPage = page
        select?(page)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishSwipe()
    }

    /// Passing the keyboard holds everything up for about a tenth of a second. A finger that
    /// caught the pager as it bounced back from past the first or last page was held up with it,
    /// and the pull it started caught, so the keyboard waits for the finger to let go.
    private func finishSwipe() {
        guard let page = pageAwaitingFocus else { return }
        guard isStill(showing: page) else {
            waitToPassKeyboard()
            return
        }
        pageAwaitingFocus = nil
        guard keyboardIsUp else { return }
        passKeyboard(to: page)
    }

    /// Whether nothing moves and no finger is down: the pager rests on a page, and the page isn't
    /// being scrolled either.
    private func isStill(showing page: Int) -> Bool {
        let views: [UIScrollView] = [scrollView, controllers[page].textView]
        guard !views.contains(where: { $0.isTracking || $0.isDragging || $0.isDecelerating }) else { return false }
        // Caught as it bounced back, the pager stops where it is and says it has come to rest.
        let x = scrollView.contentOffset.x
        return x > -0.5 && x < max(0, scrollView.contentSize.width - scrollView.bounds.width) + 0.5
    }

    /// Looks again in a moment: let go of without being dragged, the pager may not call back.
    private func waitToPassKeyboard() {
        guard !isWaitingToPassKeyboard else { return }
        isWaitingToPassKeyboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isWaitingToPassKeyboard = false
            self?.finishSwipe()
        }
    }
}

/// Holds the pager and the format bar, and measures how much of it the keyboard covers with
/// UIKit's keyboard layout guide. Unlike keyboard notifications, the guide tracks the keyboard
/// frame by frame while it's swiped away, and animates with it when it comes and goes.
///
/// The bar rides on top of the keys, following the guide. As the text view's input accessory
/// it vanished before the keys when a swipe dismissed the keyboard: iOS docks or drops an
/// accessory the moment the finger lifts, while the keys are still sliding away.
final class PagerContainerView: UIView {
    let scrollView = PagerScrollView()
    /// Reports how much of this view the keyboard and the format bar cover.
    var onKeyboardOverlapChange: ((CGFloat) -> Void)?
    /// Reports the dot bar going up out of the way of the keys, or coming back, with the keys'
    /// animation, for SwiftUI.
    var onTopBarAwayChange: ((Bool, Animation?) -> Void)?
    /// The editor that has the keyboard, if any. The bar only ever shows for one.
    var editingTextView: () -> UITextView? = { nil }
    /// Set while Writing Tools is at work on the page being edited. It brings controls of its own,
    /// so the bar slides down into the keys meanwhile. Writing Tools puts its panel where the keys
    /// were, and once it's done the keys come back up from the bottom of the screen; the bar waits
    /// for them there and rises with them. Back at once, it slid up onto the panel as the panel
    /// went, and then sat high above the keys while they came up.
    var isWritingToolsAtWork = false {
        didSet {
            guard isWritingToolsAtWork != oldValue else { return }
            if isWritingToolsAtWork {
                keysWhenWritingToolsEnded = nil
                UIView.animate(withDuration: 0.25) { self.placeBar() }
                return
            }
            keysWhenWritingToolsEnded = keys
            // Keys that don't come back, or come back just as tall, give no sign.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.isWritingToolsAtWork, self.keysWhenWritingToolsEnded != nil else { return }
                self.keysWhenWritingToolsEnded = nil
                UIView.animate(withDuration: 0.25) { self.placeBar() }
            }
        }
    }
    /// How tall the keys stood as Writing Tools finished, until they change: the bar waits for them.
    private var keysWhenWritingToolsEnded: CGFloat?
    /// The keys the bar stays on while they're gone for a moment, the page still being edited.
    /// Siri takes the keys for its own and gives them back, and each time UIKit first says they've
    /// gone, then a few milliseconds later that they're back. Following that, the bar dipped and
    /// bounced back as Siri came, and fell and then dropped back down from above as it went.
    private var keysThatVanished: CGFloat?
    /// The size this view was last laid out at, and when it last changed, as the phone turned.
    /// Turning upright, UIKit takes the keys down, says they're going, and puts them straight back
    /// up for the new way up: the bar went down into them and was gone for the turn.
    private var laidOutSize: CGSize = .zero
    private var turnedAt: ContinuousClock.Instant?
    private var vanishedKeysRelease = 0
    /// The keys as last measured, before any held in their place.
    private var measuredKeys: CGFloat = 0
    /// Set once UIKit says the keys are going, until they come back up or it says they're coming.
    /// Keys going for good say so first, as when Writing Tools takes their place, and the bar goes
    /// down with them.
    private var keysAreGoing = false
    private let keyboardProbe = UIView()
    /// Its bottom edge is the top of the keys, and it clips the bar, so a bar sliding into the
    /// keyboard never shows through the keyboard's translucent top.
    private let barTrack = PassthroughView()
    private let formatBar = FormatBar.shared
    private var reportedOverlap: CGFloat = 0
    private var reportedTopBarAway = false
    /// Whether on-screen keys are up, with the bar on top of them.
    private var barRidesOnKeys = false
    /// How far the bar has slid down into the keys: 0 while it sits on top of them, its full
    /// height when hidden.
    private var barSink = FormatBar.height
    /// How tall the bar stands: a row taller while a link is being changed in it.
    private var barHeight: CGFloat { formatBar.height }
    private var laidOutKeys: CGFloat = 0
    /// Room above the bar inside its track, so the glass's soft edge isn't clipped.
    private let trackHeadroom: CGFloat = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(scrollView)

        // With the keyboard down, the guide sits at the very bottom instead of the safe area.
        keyboardLayoutGuide.usesBottomSafeArea = false
        keyboardProbe.isHidden = true
        keyboardProbe.isUserInteractionEnabled = false
        keyboardProbe.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboardProbe)
        NSLayoutConstraint.activate([
            keyboardProbe.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardProbe.widthAnchor.constraint(equalToConstant: 1),
            keyboardProbe.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            keyboardProbe.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        barTrack.clipsToBounds = true
        formatBar.frame.origin.y = trackHeadroom + barSink
        barTrack.addSubview(formatBar)
        addSubview(barTrack)
        formatBar.onHeightChange = { [weak self] in self?.barHeightChanged() }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keysWillGo), name: UIResponder.keyboardWillHideNotification, object: nil)
        center.addObserver(self, selector: #selector(keysWillCome), name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Runs on every step of a keyboard drag, and inside the keyboard's own animation when it
    /// comes or goes.
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize {
            if laidOutSize != .zero { turnedAt = .now }
            laidOutSize = bounds.size
        }
        placeBar()
    }

    /// How tall the keys stand over the bottom of this view.
    private var keys: CGFloat {
        #if DEBUG
        if let keysForTesting { return keysForTesting }
        #endif
        return max(0, keyboardProbe.frame.height)
    }

    #if DEBUG
    /// Keys of this height, in place of the system keyboard's, which tests don't have.
    var keysForTesting: CGFloat?

    /// Where the bar's track is: its bottom edge is the top of the keys the bar rides on.
    var barTrackFrameForTesting: CGRect { barTrack.frame }

    /// Whether the bar's track is moving, in an animation of its own or one it's carried by.
    var barTrackIsMovingForTesting: Bool { !(barTrack.layer.animationKeys() ?? []).isEmpty }

    /// UIKit saying the keys are going, as it does turning the phone upright.
    func keyboardWillHideForTesting() {
        keysWillGo()
    }

    /// How many times the bar has stopped riding on the keys, to go down into them.
    private(set) var timesBarLeftKeysForTesting = 0
    #endif

    /// Puts the bar on top of the keys, or away, and reports how much of this view they cover.
    private func placeBar() {
        var keys = self.keys
        let editor = editingTextView()
        if keys > measuredKeys { keysAreGoing = false }
        if keys == 0, measuredKeys > 0, keysMayComeRightBack(to: editor) || keysTurnWithPhone(editor) {
            holdVanishedKeys(measuredKeys)
        }
        measuredKeys = keys
        if let vanished = keysThatVanished {
            if keys > 0 || isWritingToolsAtWork || editor == nil {
                keysThatVanished = nil
            } else {
                keys = vanished
            }
        }
        if let ended = keysWhenWritingToolsEnded, abs(keys - ended) > 0.5 {
            keysWhenWritingToolsEnded = nil
        }
        // While Writing Tools is at work, and until the keys come back after it, the bar waits
        // at the bottom of the screen (see `isWritingToolsAtWork`).
        let barKeys = isWritingToolsAtWork || keysWhenWritingToolsEnded != nil ? 0 : keys
        // On-screen keys stand well over 120 points. A hardware keyboard leaves no keys, or only a
        // short strip, and the bar stays away. Keys dragged partway down still carry it.
        #if DEBUG
        let wasRiding = barRidesOnKeys
        defer { if wasRiding, !barRidesOnKeys { timesBarLeftKeysForTesting += 1 } }
        #endif
        if editor == nil || barKeys == 0 {
            barRidesOnKeys = false
        } else if barKeys > 120 {
            barRidesOnKeys = true
        } else if editor?.isTracking != true {
            barRidesOnKeys = false
        }

        // The track moves exactly like the keys: inside the keyboard's animation it gets the same
        // one. The bar stays on top of the keys all the way down; only once they're nearly gone
        // does it slide in after them, so both leave the screen together.
        let trackHeight = barHeight + trackHeadroom
        let track = CGRect(x: 0, y: bounds.height - barKeys - trackHeight, width: bounds.width, height: trackHeight)
        if barTrack.frame != track {
            // Keys that jump into place, as the page's do when a drawer over it closes, leave
            // nothing of an earlier move playing out: the track, still sliding after keys that had
            // been going down, showed the bar high above them and slid it down onto them. Not while
            // the phone turns: the turn's own animation carries the track with this view's bottom,
            // and the keys for the new way up come a moment into the turn, outside it. Put straight
            // where it ends, the track went below the bottom, out of sight for the turn upright.
            let isInTurn = (layer.animationKeys() ?? []).contains { $0.hasPrefix("bounds") }
            if UIView.inheritedAnimationDuration == 0, !isInTurn { barTrack.layer.removeAllAnimations() }
            barTrack.frame = track
        }
        moveBar(keysFrom: laidOutKeys, to: barKeys)
        laidOutKeys = barKeys

        // On a phone on its side the keys leave the page a few lines, and the dot bar goes up out
        // of their way while they're up (user, 2026-10-05), with them, and comes back as they go.
        let isTopBarAway = barRidesOnKeys && (!keysAreGoing || isTurning) && traitCollection.verticalSizeClass == .compact
        if isTopBarAway != reportedTopBarAway {
            reportedTopBarAway = isTopBarAway
            onTopBarAwayChange?(isTopBarAway, keysAnimation())
        }

        formatBar.accessibilityElementsHidden = !barRidesOnKeys
        let overlap = keys + barHeight - barSink
        guard abs(overlap - reportedOverlap) > 0.5 else { return }
        reportedOverlap = overlap
        onKeyboardOverlapChange?(overlap)
    }

    /// Whether a link on `page` can be changed in the bar: the page is being edited, with the bar
    /// on its keys. With no keys on screen, as with a hardware keyboard, there's no bar to change
    /// it in. A drawer's fields did take the keys, but sent them down and back up.
    func canEditLinks(on page: EditorController) -> Bool {
        barRidesOnKeys && !isWritingToolsAtWork && editingTextView() === page.textView && formatBar.editor === page
    }

    /// Shows `link` in the bar, to change on the keys, if it can be (`canEditLinks`). Says whether
    /// it did.
    @discardableResult
    func editLinkOnKeys(_ link: EditorController.PageLink, of page: EditorController) -> Bool {
        guard canEditLinks(on: page) else { return false }
        return formatBar.editLink(link)
    }

    /// The bar grew a row for a link, or went back down: it stays on the keys, growing up from
    /// them, and the page's room for it changes along with it, the link's text kept in view.
    private func barHeightChanged() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.placeBar()
            self.formatBar.layoutIfNeeded()
        }
    }

    /// A page took the keyboard back as a drawer over it went: UIKit brings its keys straight back
    /// up, with no animation to carry the bar up with them. It slides up out of them on its own.
    /// Keys coming up with the page carry it as ever.
    func pageTookKeys() {
        guard keys > 120, !barRidesOnKeys, editingTextView() != nil, !isWritingToolsAtWork else { return }
        UIView.animate(withDuration: 0.25) { self.placeBar() }
    }

    /// Whether the phone turned a moment ago.
    private var isTurning: Bool {
        guard let turnedAt else { return false }
        return ContinuousClock.now - turnedAt < .milliseconds(600)
    }

    /// Whether keys that just vanished from under the page being edited are being turned with the
    /// phone, to come straight back for the new way up, whatever UIKit said.
    private func keysTurnWithPhone(_ editor: UITextView?) -> Bool {
        guard let editor, isTurning else { return false }
        return (editor as? BiteTextView)?.isResigning != true
    }

    /// Whether keys that just vanished from under the page being edited may be back in a moment:
    /// nothing put them away, and nothing said they were going.
    private func keysMayComeRightBack(to editor: UITextView?) -> Bool {
        guard let editor, !editor.isTracking, (editor as? BiteTextView)?.isResigning != true,
              !keysAreGoing, !isWritingToolsAtWork else { return false }
        return window?.windowScene?.activationState == .foregroundActive
    }

    private func holdVanishedKeys(_ keys: CGFloat) {
        keysThatVanished = keys
        vanishedKeysRelease += 1
        let release = vanishedKeysRelease
        // Keys still gone a moment later have gone for good, as for a hardware keyboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.vanishedKeysRelease == release else { return }
            self.letVanishedKeysGo()
        }
    }

    private func letVanishedKeysGo() {
        guard keysThatVanished != nil else { return }
        keysThatVanished = nil
        UIView.animate(withDuration: 0.25) { self.placeBar() }
    }

    @objc private func keysWillGo() {
        keysAreGoing = true
        // Said as the phone turns upright, of keys coming straight back.
        if !isTurning { letVanishedKeysGo() }
    }

    @objc private func keysWillCome() {
        keysAreGoing = false
    }

    /// How far the bar sinks into keys that stand `keys` points tall.
    private func sink(onKeys keys: CGFloat) -> CGFloat {
        max(0, barHeight - keys)
    }

    private func moveBar(keysFrom start: CGFloat, to end: CGFloat) {
        let target = barRidesOnKeys ? sink(onKeys: end) : barHeight
        let barFrame = { (sink: CGFloat) in
            CGRect(x: 0, y: self.trackHeadroom + sink, width: self.bounds.width, height: self.barHeight)
        }
        guard target != barSink else {
            // Still headed to the same place, maybe mid-animation; only its size can change: the
            // width, and the height as a link comes and goes.
            if formatBar.bounds.size != barFrame(target).size {
                formatBar.frame = barFrame(target)
            }
            return
        }
        let layer = formatBar.layer
        var from = barSink
        if layer.animation(forKey: Self.sinkKey) != nil, let shown = layer.presentation() {
            // Interrupted mid-way: carry on from where the bar is on screen.
            from = shown.frame.minY - trackHeadroom
            layer.removeAnimation(forKey: Self.sinkKey)
        }
        barSink = target
        let keyboard = UIView.inheritedAnimationDuration > 0 ? keyboardAnimation() : nil
        guard let keyboard else {
            // Following a finger, or inside some other animation, which then carries the bar along.
            formatBar.frame = barFrame(target)
            return
        }
        UIView.performWithoutAnimation { formatBar.frame = barFrame(target) }
        // The sink has a corner in it (none until the keys are nearly gone), which no single
        // animation between two values can follow. Keyframes on the keyboard's own timing can.
        let followsKeys = from == sink(onKeys: start) && target == sink(onKeys: end)
        let sinkAt = { (progress: CGFloat) -> CGFloat in
            followsKeys ? self.sink(onKeys: start + (end - start) * progress) : from + (target - from) * progress
        }
        let animation = CAKeyframeAnimation(keyPath: "position.y")
        animation.beginTime = keyboard.beginTime
        animation.duration = keyboard.duration
        animation.fillMode = .backwards
        var progress: [CGFloat] = []
        if let spring = keyboard as? CASpringAnimation {
            // Keyframes can't take a spring's timing, so sample the spring itself.
            let steps = 60
            let times = (0...steps).map { CGFloat($0) / CGFloat(steps) }
            progress = times.map { Self.progress(of: spring, at: Double($0) * spring.duration) }
            animation.keyTimes = times.map { NSNumber(value: Double($0)) }
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
        } else {
            // The keyboard's curve maps time to progress for the bar too, so sampling progress is
            // exact, corner included.
            var samples = (0...24).map { CGFloat($0) / 24 }
            if followsKeys, start != end {
                let corner = (start - barHeight) / (start - end)
                if corner > 0, corner < 1 { samples.append(corner) }
            }
            progress = samples.sorted()
            animation.keyTimes = progress.map { NSNumber(value: Double($0)) }
            animation.timingFunction = keyboard.timingFunction
        }
        let centerY = trackHeadroom + barHeight / 2
        animation.values = progress.map { centerY + sinkAt($0) }
        layer.add(animation, forKey: Self.sinkKey)
    }

    private static let sinkKey = "sink"

    /// The animation the keys are moving with, as SwiftUI's, or none outside one.
    private func keysAnimation() -> Animation? {
        guard UIView.inheritedAnimationDuration > 0 else { return nil }
        let keyboard = keyboardAnimation()
        if let spring = keyboard as? CASpringAnimation {
            return .interpolatingSpring(mass: Double(spring.mass), stiffness: Double(spring.stiffness),
                                        damping: Double(spring.damping), initialVelocity: Double(spring.initialVelocity))
        }
        return .easeInOut(duration: keyboard?.duration ?? UIView.inheritedAnimationDuration)
    }

    /// The animation UIKit just gave the track, which is the keyboard's.
    private func keyboardAnimation() -> CAPropertyAnimation? {
        let layer = barTrack.layer
        return (layer.animationKeys() ?? [])
            .compactMap { layer.animation(forKey: $0) as? CAPropertyAnimation }
            .filter { $0.keyPath == "position" }
            .max { $0.beginTime < $1.beginTime }
    }

    /// How far along a spring is at `time`, from 0 at the start to 1 at rest.
    private static func progress(of spring: CASpringAnimation, at time: Double) -> CGFloat {
        let omega = sqrt(Double(spring.stiffness / spring.mass))
        let zeta = Double(spring.damping) / (2 * sqrt(Double(spring.stiffness * spring.mass)))
        let velocity = Double(spring.initialVelocity)
        let remaining: Double
        if abs(zeta - 1) < 0.001 {
            remaining = exp(-omega * time) * (1 + (omega - velocity) * time)
        } else if zeta < 1 {
            let damped = omega * sqrt(1 - zeta * zeta)
            remaining = exp(-zeta * omega * time)
                * (cos(damped * time) + (zeta * omega - velocity) / damped * sin(damped * time))
        } else {
            let root = sqrt(zeta * zeta - 1)
            let r1 = -omega * (zeta - root), r2 = -omega * (zeta + root)
            let a = (-velocity - r2) / (r1 - r2)
            remaining = a * exp(r1 * time) + (1 - a) * exp(r2 * time)
        }
        return CGFloat(1 - remaining)
    }
}

/// Lets touches through wherever it has nothing of its own under them.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

final class PagerScrollView: UIScrollView {
    var pageViews: [UIView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            pageViews.forEach { addSubview($0) }
            setNeedsLayout()
        }
    }
    var currentPage = 0
    private var isChangingPage = false
    private var laidOutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isPagingEnabled = true
        isDirectionalLockEnabled = true
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Lands on `page` at once. From the dot bar, sliding past every page in between was slow to
    /// follow a finger moving along the dots.
    func go(to page: Int) {
        currentPage = page
        isChangingPage = true
        setContentOffset(CGPoint(x: CGFloat(page) * bounds.width, y: 0), animated: false)
        isChangingPage = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0 else { return }
        // After a resize (first layout, rotation), the current page goes back in place first. The
        // pages narrowing under the old place, as the phone turned upright, put the pager on the
        // last page for a moment, which it reported, with a tick, and the dot bar stayed on it.
        if size.width != laidOutWidth {
            laidOutWidth = size.width
            contentOffset = CGPoint(x: CGFloat(currentPage) * size.width, y: 0)
        }
        for (index, view) in pageViews.enumerated() {
            let frame = CGRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
            if view.frame != frame { view.frame = frame }
        }
        let contentSize = CGSize(width: size.width * CGFloat(pageViews.count), height: size.height)
        if self.contentSize != contentSize { self.contentSize = contentSize }
    }

    /// UIKit scrolls ancestor scroll views to reveal a first responder's caret. That must never
    /// flip the page; only swipes and the dot bar do.
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {}

    override func setContentOffset(_ offset: CGPoint, animated: Bool) {
        let staysOnPage = abs(offset.x - CGFloat(currentPage) * bounds.width) < 1
        guard isChangingPage || isTracking || staysOnPage else { return }
        super.setContentOffset(offset, animated: animated)
    }
}
