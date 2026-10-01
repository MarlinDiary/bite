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
        container.editingTextView = { [weak self] in
            self?.controllers.first { $0.textView.isFirstResponder }?.textView
        }
    }

    /// Tapping the status bar scrolls to the top only when a single scroll view on screen asks
    /// for it, so only the page on screen does: not the pager, nor the pages beside it.
    func letPageScrollToTop(_ page: Int) {
        for controller in controllers {
            controller.textView.scrollsToTop = controller.dot == page
        }
    }

    private var keyboardIsUp: Bool {
        controllers.contains { $0.textView.isFirstResponder }
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
        if lastVisiblePage != nil {
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
    /// The editor that has the keyboard, if any. The bar only ever shows for one.
    var editingTextView: () -> UITextView? = { nil }
    private let keyboardProbe = UIView()
    /// Its bottom edge is the top of the keys, and it clips the bar, so a bar sliding into the
    /// keyboard never shows through the keyboard's translucent top.
    private let barTrack = PassthroughView()
    private let formatBar = FormatBar.shared
    private var reportedOverlap: CGFloat = 0
    /// Whether on-screen keys are up, with the bar on top of them.
    private var barRidesOnKeys = false
    /// How far the bar has slid down into the keys: 0 while it sits on top of them, its full
    /// height when hidden.
    private var barSink = FormatBar.height
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Runs on every step of a keyboard drag, and inside the keyboard's own animation when it
    /// comes or goes.
    override func layoutSubviews() {
        super.layoutSubviews()
        let keys = max(0, keyboardProbe.frame.height)
        let editor = editingTextView()
        // On-screen keys stand well over 120 points. A hardware keyboard leaves no keys, or only a
        // short strip, and the bar stays away. Keys dragged partway down still carry it.
        if editor == nil || keys == 0 {
            barRidesOnKeys = false
        } else if keys > 120 {
            barRidesOnKeys = true
        } else if editor?.isTracking != true {
            barRidesOnKeys = false
        }

        // The track moves exactly like the keys: inside the keyboard's animation it gets the same
        // one. The bar stays on top of the keys all the way down; only once they're nearly gone
        // does it slide in after them, so both leave the screen together.
        let trackHeight = FormatBar.height + trackHeadroom
        let track = CGRect(x: 0, y: bounds.height - keys - trackHeight, width: bounds.width, height: trackHeight)
        if barTrack.frame != track { barTrack.frame = track }
        moveBar(keysFrom: laidOutKeys, to: keys)
        laidOutKeys = keys

        formatBar.accessibilityElementsHidden = !barRidesOnKeys
        let overlap = keys + FormatBar.height - barSink
        guard abs(overlap - reportedOverlap) > 0.5 else { return }
        reportedOverlap = overlap
        onKeyboardOverlapChange?(overlap)
    }

    /// How far the bar sinks into keys that stand `keys` points tall.
    private func sink(onKeys keys: CGFloat) -> CGFloat {
        max(0, FormatBar.height - keys)
    }

    private func moveBar(keysFrom start: CGFloat, to end: CGFloat) {
        let target = barRidesOnKeys ? sink(onKeys: end) : FormatBar.height
        let barFrame = { (sink: CGFloat) in
            CGRect(x: 0, y: self.trackHeadroom + sink, width: self.bounds.width, height: FormatBar.height)
        }
        guard target != barSink else {
            // Still headed to the same place, maybe mid-animation; only the width can change.
            if formatBar.bounds.width != bounds.width {
                formatBar.frame.size.width = bounds.width
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
                let corner = (start - FormatBar.height) / (start - end)
                if corner > 0, corner < 1 { samples.append(corner) }
            }
            progress = samples.sorted()
            animation.keyTimes = progress.map { NSNumber(value: Double($0)) }
            animation.timingFunction = keyboard.timingFunction
        }
        let centerY = trackHeadroom + FormatBar.height / 2
        animation.values = progress.map { centerY + sinkAt($0) }
        layer.add(animation, forKey: Self.sinkKey)
    }

    private static let sinkKey = "sink"

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
        for (index, view) in pageViews.enumerated() {
            let frame = CGRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
            if view.frame != frame { view.frame = frame }
        }
        let contentSize = CGSize(width: size.width * CGFloat(pageViews.count), height: size.height)
        if self.contentSize != contentSize { self.contentSize = contentSize }
        // After a resize (first layout, rotation), put the current page back in place.
        if size.width != laidOutWidth {
            laidOutWidth = size.width
            contentOffset = CGPoint(x: CGFloat(currentPage) * size.width, y: 0)
        }
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
