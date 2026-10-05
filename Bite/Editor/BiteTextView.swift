import UIKit
import BiteKit

/// The UITextView behind each dot. It hands backspace, paste, copy and checkbox taps to its
/// `EditorController` and leaves room at the top for the dot bar.
final class BiteTextView: UITextView {
    weak var editor: EditorController?

    private let contentStorage = NSTextContentStorage()
    private let finalNewlineDelegate = FinalNewlineDelegate()
    private lazy var checkboxTap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
    private lazy var linkTap = UITapGestureRecognizer(target: self, action: #selector(handleLinkTap(_:)))
    /// Puts found text out as a finger lands. The text view's own `touchesBegan` missed a quick
    /// tap: UIKit's text tap took the touch before it got there.
    private let touchDown = TouchDownRecognizer()
    /// Air above the first line, under the dot bar.
    private let airOverText: CGFloat = 24
    /// Room under the last line when scrolled to the end.
    private let bottomTextInset: CGFloat = 28
    /// More room under the last line while typing, so the line being written can sit a couple
    /// of lines above the keyboard rather than pressed against it.
    private let typingRoom: CGFloat = 44
    private var needsCaretScroll = false

    /// How much of this view the keyboard and the format bar on top of it cover. The pager
    /// measures it with UIKit's keyboard layout guide, which also follows the keyboard while it's
    /// swiped away. The view itself keeps its full height; resizing the editor made the text jump.
    var keyboardOverlap: CGFloat = 0 {
        didSet {
            guard abs(oldValue - keyboardOverlap) > 0.5 else { return }
            // With the keyboard gone, no page is ready for it any more: where it comes back, the
            // pages beside are readied again.
            if keyboardOverlap == 0 { keepsKeyboardRoom = false }
            // Keys gone while the page stays focused are most likely making way for Writing Tools,
            // which says so a moment later (see `writingToolsWillBegin`). Their room stays till then.
            if keyboardOverlap == 0, oldValue > 0, isFirstResponder, !isResigning, !isTracking, heldKeyboardOverlap == nil {
                heldKeyboardOverlap = insetKeyboardOverlap
                releaseHeldKeyboardRoom(after: 0.3)
            }
            // Back as tall as they were, the keys take their room over.
            if let held = heldKeyboardOverlap, !isHeldForWritingTools, keyboardOverlap >= held - 0.5 {
                heldKeyboardOverlap = nil
            }
            applyKeyboardInset()
            // Keep the caret clear of a keyboard that's coming up.
            if keyboardOverlap > oldValue, !isTracking {
                requestCaretScroll()
            }
        }
    }

    /// The keyboard overlap the scroll insets account for.
    private var insetKeyboardOverlap: CGFloat = 0

    /// Only the page being edited makes room for the keyboard. As soon as editing ends the
    /// keyboard is on its way out, so the room goes in the same animation, all at once. It used
    /// to shrink in two steps and the second one, which ran outside any animation, made the
    /// text jump.
    private var wantedKeyboardOverlap: CGFloat {
        let overlap = (isFirstResponder && !isResigning) || keepsKeyboardRoom ? keyboardOverlap : 0
        guard let held = heldKeyboardOverlap, isFirstResponder, !isResigning else { return overlap }
        return max(overlap, held)
    }

    /// The room kept for keys that went away while the page stayed focused, as they do for Writing
    /// Tools: it puts a shorter panel of its own where they were, and brings them back once it's
    /// done. The text stays where it was all the while. It moved down as the keys went and up as
    /// they came back, and coming back it jumped: Writing Tools holds everything up for a moment
    /// as it finishes, and the scroll back to the selection was held up with it.
    private var heldKeyboardOverlap: CGFloat?
    private var isHeldForWritingTools = false
    /// Which release is due, so an earlier one doesn't end a later hold.
    private var keyboardRoomRelease = 0

    /// Writing Tools is starting on the page. The keys' room stays while it works.
    func writingToolsWillBegin() {
        isHeldForWritingTools = true
        if heldKeyboardOverlap == nil, insetKeyboardOverlap > 0 {
            heldKeyboardOverlap = insetKeyboardOverlap
        }
    }

    /// Writing Tools is done. The room stays until the keys are back, or for a moment.
    func writingToolsDidEnd() {
        isHeldForWritingTools = false
        if let held = heldKeyboardOverlap, keyboardOverlap >= held - 0.5 {
            heldKeyboardOverlap = nil
        } else {
            releaseHeldKeyboardRoom(after: 0.5)
        }
    }

    private func releaseHeldKeyboardRoom(after delay: TimeInterval) {
        keyboardRoomRelease += 1
        let release = keyboardRoomRelease
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.keyboardRoomRelease == release, !self.isHeldForWritingTools,
                  self.heldKeyboardOverlap != nil else { return }
            self.heldKeyboardOverlap = nil
            self.applyKeyboardInset()
        }
    }

    /// Set on a page beside the one being edited: readied to be swiped to (`arrive`), or just
    /// swiped away from. It keeps its room for the keyboard, and so its place by the caret, so
    /// a swipe to it has nothing left to do. The room still goes when the keyboard does.
    private(set) var keepsKeyboardRoom = false {
        didSet { wasScrolledSinceReady = false }
    }

    /// Set when a page ready for the keyboard is scrolled by hand before it takes it. It then
    /// stays where it was scrolled to: taking the keyboard scrolled it back to the caret.
    private var wasScrolledSinceReady = false
    /// The selection as that page took the keyboard. UIKit scrolls to it then, and again once the
    /// keyboard says it's up; neither happens until the selection changes.
    private var selectionNotToScrollTo: NSRange?

    /// UIKit starts the keyboard's exit animation inside `resignFirstResponder`, while this view
    /// still reports being first responder.
    private(set) var isResigning = false

    private func applyKeyboardInset() {
        updateScrollIndicatorInsets()
        guard abs(insetKeyboardOverlap - wantedKeyboardOverlap) > 0.5 else { return }
        // Changing the inset under a finger clamps the scroll position on every frame, which made
        // the text shudder while the keyboard was dragged away. Nor does it change while the page
        // springs back from past its top or end, as one let go of there does: UIKit put the page
        // back in range at once, under the spring, and the text dropped and crept back up as the
        // keyboard left. It waits only until the page is back in range, though, not until it stops
        // scrolling: the room a swiped-away keyboard left stayed open until then, half a second
        // too long.
        guard !isTracking, !(isDecelerating && isPastEitherEnd) else {
            waitToApplyKeyboardInset()
            return
        }
        let apply = {
            self.insetKeyboardOverlap = self.wantedKeyboardOverlap
            self.updateInsets()
        }
        // Inside the keyboard's own animation the change rides along with it; otherwise give it
        // one, so a shorter page slides into place instead of snapping. A page off screen, one
        // the keyboard has just moved away from, takes it at once: still running when a quick
        // swipe brought the page back, the animation moved its text as it came in.
        if UIView.inheritedAnimationDuration > 0 {
            apply()
        } else if isOnScreen {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
        } else {
            UIView.performWithoutAnimation(apply)
        }
    }

    /// Whether the page is scrolled past its top or its end, as while it springs back.
    private var isPastEitherEnd: Bool {
        let top = -contentInset.top
        let end = max(top, contentSize.height + contentInset.bottom - bounds.height)
        return contentOffset.y < top - 0.5 || contentOffset.y > end + 0.5
    }

    private var isWaitingToApplyKeyboardInset = false

    /// Looks again in a moment, until the page is let go of and back in range. UIKit reports the
    /// end of a drag (`dragDidEnd`) while it still counts the finger as down.
    private func waitToApplyKeyboardInset() {
        guard !isWaitingToApplyKeyboardInset else { return }
        isWaitingToApplyKeyboardInset = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.isWaitingToApplyKeyboardInset = false
            self.applyKeyboardInset()
        }
    }

    /// Whether any of the page shows: the pages beside it sit off screen in the pager.
    private var isOnScreen: Bool {
        guard let window else { return false }
        return convert(bounds, to: window).intersects(window.bounds)
    }

    /// Called by the editor when the finger lifts at the end of a drag.
    func dragDidEnd() {
        if keepsKeyboardRoom, !isFirstResponder { wasScrolledSinceReady = true }
        applyKeyboardInset()
    }

    /// Set while a page takes the keys, before it has them: what had them has given them up.
    private(set) static var isTakingKeys = false

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let keepsPlace = wasScrolledSinceReady && !isFirstResponder
        Self.isTakingKeys = true
        let became = super.becomeFirstResponder()
        Self.isTakingKeys = false
        // Taken from a link in the format bar, which lets it go now the page has them.
        FormatBar.shared.pageTookKeys()
        if became, keepsPlace { selectionNotToScrollTo = selectedRange }
        // Moving to this page with the keyboard already up: nothing else will tell it.
        if became {
            keepsKeyboardRoom = false
            applyKeyboardInset()
        }
        return became
    }

    /// Puts a page about to be moved to with the keyboard up where editing it will scroll it,
    /// before it's on screen: room made for the keyboard and the caret in view, all at once. The
    /// page used to arrive where it was, often the top, and then scroll down to the caret.
    func arrive() {
        keepsKeyboardRoom = true
        // Whatever was still moving the page, a scroll or a change of its room for the keyboard,
        // stops where it is, so nothing is left to play out as it comes in.
        layer.removeAllAnimations()
        setContentOffset(contentOffset, animated: false)
        UIView.performWithoutAnimation {
            updateScrollIndicatorInsets()
            if abs(insetKeyboardOverlap - keyboardOverlap) > 0.5 {
                insetKeyboardOverlap = keyboardOverlap
                updateInsets()
            }
            // Text not laid out yet has estimated heights, so the caret found far down is where
            // it's estimated to be. Laid out where the page goes, it's where it really is.
            for _ in 0..<3 {
                layoutIfNeeded()
                guard let target = caretScrollTarget() else { break }
                setContentOffset(CGPoint(x: contentOffset.x, y: target), animated: false)
            }
        }
    }

    /// Scrolls `range` into view a little below the dot bar, as at a search result picked
    /// outside Bite: where the eye goes first, with a few lines before it. In view already, it
    /// stays where it is.
    func show(_ range: NSRange) {
        guard let start = position(from: beginningOfDocument, offset: range.location) else { return }
        // Text not laid out yet has estimated heights, so a line found far down is where it's
        // estimated to be. Laid out where the page goes, it's where it really is.
        for _ in 0..<3 {
            layoutIfNeeded()
            let line = caretRect(for: start)
            guard !line.isNull, !line.isInfinite else { return }
            let visibleTop = contentOffset.y + topObstruction
            let visibleBottom = contentOffset.y + bounds.height - bottomObstruction
            guard line.minY < visibleTop || line.maxY > visibleBottom else { return }
            let maxOffset = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
            let target = min(max(line.minY - topObstruction - (visibleBottom - visibleTop) / 4, -contentInset.top), maxOffset)
            guard abs(target - contentOffset.y) > 0.5 else { return }
            setContentOffset(CGPoint(x: contentOffset.x, y: target), animated: false)
        }
    }

    /// For the page giving the keyboard up to another: it's likely swiped back to.
    func keepKeyboardRoom() {
        keepsKeyboardRoom = true
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        // What an input method is still composing goes in as it stands, as when a tap lands
        // elsewhere in the text. Left marked on a page no longer being edited, as when another
        // dot was picked, it went unsaved, and the next word composed there replaced it.
        if markedTextRange != nil { unmarkText() }
        selectionNotToScrollTo = nil
        heldKeyboardOverlap = nil
        isHeldForWritingTools = false
        isResigning = true
        defer {
            isResigning = false
            // In case the keyboard's animation didn't pass through here, catch up now.
            applyKeyboardInset()
        }
        return super.resignFirstResponder()
    }

    /// Builds the TextKit 2 stack by hand. `UITextView(usingTextLayoutManager:)` goes through a
    /// private initializer that skips this subclass's stored property defaults.
    init() {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        contentStorage.delegate = finalNewlineDelegate
        contentStorage.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure() {
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        contentInsetAdjustmentBehavior = .never
        // The insets below already allow for the safe area; UIKit would add it a second time.
        automaticallyAdjustsScrollIndicatorInsets = false
        smartDashesType = .no
        // Notes go down fast and as typed: nothing gets changed behind the writer's back. A
        // correction the keyboard had lined up also went in on any tap of the format bar.
        autocorrectionType = .no
        inlinePredictionType = .no
        spellCheckingType = checkedSpelling
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange),
                                               name: Preferences.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        // Smart delete tidies the spaces around a deleted word, and deleted more than it said it
        // would: emptying the last line of a code block took the line break with it, so the line
        // was gone and typing went into the line below.
        smartInsertDeleteType = .no
        allowsEditingTextAttributes = false
        textContainer.lineFragmentPadding = 0
        addGestureRecognizer(checkboxTap)
        addGestureRecognizer(linkTap)
        touchDown.onTouchDown = { [weak self] in self?.hideFound() }
        addGestureRecognizer(touchDown)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BiteTextView, _) in
            view.setNeedsLayout()
        }
        updateInsets()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // SwiftUI hosts this view edge to edge, so its own safe area is zero; the window's isn't.
        updateInsets()
        // Text layout has just run here too, so the code blocks and the lines' marks can follow it
        // in the same frame.
        updateCodeBackgrounds()
        updateLineMarks()
        drawFound()
        // Text layout has just run, so the caret rect is final.
        if needsCaretScroll {
            needsCaretScroll = false
            if placeAcrossTurn == nil { scrollCaretIntoView(animated: true) }
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateInsets()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateInsets()
    }

    private var safeTop: CGFloat {
        max(safeAreaInsets.top, window?.safeAreaInsets.top ?? 0)
    }

    private var safeBottom: CGFloat {
        max(safeAreaInsets.bottom, window?.safeAreaInsets.bottom ?? 0)
    }

    /// Room beside the Dynamic Island and the rounded corners, in landscape. Taken from the window,
    /// since a page's own safe area changes as it slides through the pager.
    private var safeSides: (left: CGFloat, right: CGFloat) {
        (window?.safeAreaInsets.left ?? 0, window?.safeAreaInsets.right ?? 0)
    }

    /// How far above the bottom a phone's rounded corner begins to curve inward, measured on the
    /// iPhone Air and 17 Pro screens (62-point continuous corners). Screens with a home button
    /// have square corners.
    private var cornerClearance: CGFloat {
        safeBottom > 0 ? 70 : 4
    }

    /// The status bar and the dot bar, and at the bottom the keyboard or the home indicator, are
    /// content insets: the text still scrolls under them, but UIKit knows it's out of sight
    /// there, so dragging a selection up scrolls as soon as it reaches the dot bar instead of
    /// running on under it. The air around the text is the text container's inset.
    private func updateInsets() {
        let sides = safeSides
        let textInsets = UIEdgeInsets(top: airOverText, left: 22 + sides.left, bottom: bottomTextInset, right: 22 + sides.right)
        if textContainerInset != textInsets {
            // Set before, the room beside the Dynamic Island changes as the phone turns.
            if textContainerInset.left > 0 { beginTurn() }
            textContainerInset = textInsets
        }
        let insets = UIEdgeInsets(top: topObstruction, left: 0,
                                  bottom: insetKeyboardOverlap > 0 ? insetKeyboardOverlap + typingRoom : safeBottom, right: 0)
        if contentInset != insets {
            // What's on screen stays put when the top inset first arrives or the safe area changes.
            let shift = insets.top - contentInset.top
            let offset = textStaysPut ? contentOffset.y : contentOffset.y - shift
            contentInset = insets
            // From where it was, not from where UIKit put it as the inset changed, and within the
            // page: left past its top, as after a turn back upright, UIKit put it back once the
            // turn was over, a jump.
            if shift != 0 {
                contentOffset.y = min(max(offset, -insets.top), max(-insets.top, contentSize.height + insets.bottom - bounds.height))
            }
        }
        updateScrollIndicatorInsets()
        keepPlaceAcrossTurn()
    }

    /// The indicator runs from just under the dot bar down to the format bar or, with the keyboard
    /// down, to just above where the screen's corner starts to curve. UIKit's own default stops
    /// right where the curve begins, so the indicator looked cut off by the corner. Unlike the
    /// content inset it can follow a keyboard that's being swiped away, since it never moves the
    /// text.
    private func updateScrollIndicatorInsets() {
        let insets = UIEdgeInsets(top: topObstruction, left: 0, bottom: max(wantedKeyboardOverlap, cornerClearance), right: 0)
        if verticalScrollIndicatorInsets != insets {
            verticalScrollIndicatorInsets = insets
        }
    }

    // MARK: Turning the phone

    /// The line kept in place while the page reflows to a new width, as when the phone turns: the
    /// caret's line while typing with it in view, otherwise the line at the top. The lines reflow
    /// and the dot bar and the keys move, and that line stays as far below the dot bar as it was.
    /// The page used to keep its scroll position in points, which after the reflow showed other
    /// text; and typing, it scrolled to the caret by the keys' height from before the turn, too
    /// far, then back again once the turn was over.
    private var placeAcrossTurn: PlaceOnPage?
    /// The page's width, the place on it, its selection and where it was scrolled to as the turn
    /// underway began.
    private var turnStart: (width: CGFloat, place: PlaceOnPage, selection: NSRange, offset: CGFloat)?
    /// The same from before the last turn, with where the page was left after it. Turned back with
    /// nothing changed meanwhile, the page goes back to just that place: kept in view of the keys
    /// on a phone on its side, the caret's line otherwise came back near the top.
    private var placeBeforeLastTurn: (width: CGFloat, place: PlaceOnPage, selection: NSRange, offsetAfter: CGFloat)?
    /// Which turn is underway, so an earlier one's end doesn't end a later one.
    private var turnUnderway = 0

    private typealias PlaceOnPage = (location: Int, belowTop: CGFloat)

    override var frame: CGRect {
        willSet {
            if newValue.width != frame.width { beginTurn(toWidth: newValue.width) }
        }
    }

    /// Called before the lines reflow, by whichever change comes first: the page's width, or the
    /// room beside the Dynamic Island, which turning upright takes away first.
    private func beginTurn(toWidth width: CGFloat? = nil) {
        guard frame.width > 0, window != nil, !isTracking else { return }
        if turnStart == nil, let place = placeToKeep() {
            turnStart = (frame.width, place, selectedRange, contentOffset.y)
            placeAcrossTurn = place
        }
        if let width, let start = turnStart, let before = placeBeforeLastTurn, before.width == width,
           before.selection == start.selection, abs(before.offsetAfter - start.offset) < 0.5 {
            placeAcrossTurn = before.place
        }
        turnUnderway += 1
        let turn = turnUnderway
        // The keys turn a moment after the page, in the same animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.turnUnderway == turn else { return }
            if let start = self.turnStart {
                self.placeBeforeLastTurn = (start.width, start.place, start.selection, self.contentOffset.y)
            }
            self.turnStart = nil
            self.placeAcrossTurn = nil
        }
    }

    /// The caret's line if it's being typed in and in view, else the line at the top, and how far
    /// below the dot bar it is, by the insets the page is scrolled by.
    private func placeToKeep() -> PlaceOnPage? {
        let visibleTop = contentOffset.y + contentInset.top
        let visibleBottom = contentOffset.y + bounds.height - bottomObstruction
        if isFirstResponder, let end = selectedTextRange?.end {
            let caret = caretRect(for: end)
            if !caret.isNull, !caret.isInfinite, caret.maxY > visibleTop, caret.minY < visibleBottom {
                return (offset(from: beginningOfDocument, to: end), caret.minY - visibleTop)
            }
        }
        guard let top = closestPosition(to: CGPoint(x: textContainerInset.left, y: max(visibleTop, textContainerInset.top))) else {
            return nil
        }
        let line = caretRect(for: top)
        guard !line.isNull, !line.isInfinite else { return nil }
        return (offset(from: beginningOfDocument, to: top), line.minY - visibleTop)
    }

    /// Puts the kept line back as far below the dot bar as it was, in the lines as they now
    /// reflow, and the caret in view of the keys as they now stand. It runs again as each part of
    /// the turn arrives, from where the line was, so it ends where the last of them leaves it.
    private func keepPlaceAcrossTurn() {
        guard let place = placeAcrossTurn else { return }
        guard !isTracking else {
            placeAcrossTurn = nil
            return
        }
        guard let position = position(from: beginningOfDocument, offset: place.location) else { return }
        let line = caretRect(for: position)
        guard !line.isNull, !line.isInfinite else { return }
        let top = -contentInset.top
        let end = max(top, contentSize.height + contentInset.bottom - bounds.height)
        var target = min(max(line.minY - place.belowTop - contentInset.top, top), end)
        if isFirstResponder, keyboardOverlap > 0, let caretTarget = caretScrollTarget(from: target) {
            target = caretTarget
        }
        if abs(target - contentOffset.y) > 0.5 {
            contentOffset.y = target
        }
    }

    // MARK: Keeping the caret in view

    /// UIKit asks to reveal the caret several times per keystroke, sometimes before the new line
    /// is laid out, so the text used to move in two steps. Instead, scroll once after layout, to
    /// where the caret actually is.
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        if let kept = selectionNotToScrollTo {
            if isFirstResponder, kept == selectedRange { return }
            selectionNotToScrollTo = nil
        }
        if isFirstResponder, selectedRange.length == 0 {
            requestCaretScroll()
        } else {
            super.scrollRectToVisible(rect, animated: animated)
        }
    }

    func requestCaretScroll() {
        needsCaretScroll = true
        setNeedsLayout()
    }

    /// Keeps the caret below the dot bar and, near the bottom, a comfortable couple of lines
    /// above the keyboard rather than pressed against it.
    private func scrollCaretIntoView(animated: Bool) {
        // Never move the text while a finger is on it (scrolling, or dragging the keyboard away).
        guard isFirstResponder, !isTracking, !isDragging, !isDecelerating else { return }
        // No overlap yet with an on-screen keyboard means it's still on its way; its arrival
        // triggers the one scroll that's needed, instead of two in a row.
        if keyboardOverlap == 0, !HardwareKeyboard.isConnected { return }
        guard let target = caretScrollTarget() else { return }
        setContentOffset(CGPoint(x: contentOffset.x, y: target), animated: animated)
    }

    /// Where the page scrolls to for the caret to be in view (see `scrollCaretIntoView`), or nil
    /// if it's in view where the page is, or where it would be scrolled to `offset`.
    private func caretScrollTarget(from offset: CGFloat? = nil) -> CGFloat? {
        guard let position = selectedTextRange?.end else { return nil }
        let caret = caretRect(for: position)
        guard !caret.isNull, !caret.isInfinite else { return nil }
        let start = offset ?? contentOffset.y
        let visibleTop = start + topObstruction
        let visibleBottom = start + bounds.height - bottomObstruction
        let comfort = min(96, max(0, (visibleBottom - visibleTop) * 0.25))
        var target = start
        if caret.maxY + comfort > visibleBottom {
            // Settle a little past the threshold: an empty line's caret sits a few points higher
            // than the same line once it has text, and that shouldn't cause a second nudge.
            target += caret.maxY + comfort + 16 - visibleBottom
        } else if caret.minY - 8 < visibleTop {
            target -= visibleTop - (caret.minY - 8)
        }
        let maxOffset = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        target = min(max(target, -contentInset.top), maxOffset)
        guard abs(target - start) > 0.5 else { return nil }
        return target
    }

    /// TextKit gives an empty line's caret the line spacing on top, so it stood taller there
    /// than on lines with text. Trimmed, it matches them.
    override func caretRect(for position: UITextPosition) -> CGRect {
        let position = beforeFinalNewline(position)
        var rect = super.caretRect(for: position)
        let extra = extraHeightOfEmptyLine(at: offset(from: beginningOfDocument, to: position))
        if extra > 0.5, rect.height > extra {
            rect.origin.y += extra
            rect.size.height -= extra
        }
        return rect
    }

    // Nothing reaches past the final newline, which TextKit is shown as a space (see
    // `FinalNewlineDelegate`). Dragged past the end of the last line, a selection handle took it
    // in: UIKit extends a drag beyond a line's end through its line break, whatever
    // `closestPosition` says. The highlight ran out to the edge of the page, then jumped back
    // when the finger lifted and the editor put the selection back before the newline. So the
    // selection is kept before it while dragging too, where it's drawn, and when it's set.

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        super.closestPosition(to: point).map(beforeFinalNewline)
    }

    override func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        super.closestPosition(to: point, within: range).map(beforeFinalNewline)
    }

    override var selectedTextRange: UITextRange? {
        get { super.selectedTextRange }
        set { super.selectedTextRange = newValue.map(beforeFinalNewline) }
    }

    /// The position before the final newline, if `position` is past it.
    private var lastPosition: UITextPosition? {
        position(from: beginningOfDocument, offset: max(0, textStorage.length - 1))
    }

    private func beforeFinalNewline(_ position: UITextPosition) -> UITextPosition {
        guard let last = lastPosition, compare(position, to: last) == .orderedDescending else { return position }
        return last
    }

    private func beforeFinalNewline(_ range: UITextRange) -> UITextRange {
        guard let last = lastPosition, compare(range.end, to: last) == .orderedDescending else { return range }
        return textRange(from: beforeFinalNewline(range.start), to: last) ?? range
    }

    /// How much taller than its font TextKit makes the empty line at `offset`, if it is one.
    private func extraHeightOfEmptyLine(at offset: Int) -> CGFloat {
        let string = textStorage.string as NSString
        guard offset >= 0, offset < string.length, string.character(at: offset) == 0x0A,
              offset == 0 || string.character(at: offset - 1) == 0x0A,
              let layoutManager = textLayoutManager,
              let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: offset),
              let line = layoutManager.textLayoutFragment(for: location)?.textLineFragments.first,
              let font = BlockLayoutFragment.fontOfEmptyLine(line) else { return 0 }
        return line.typographicBounds.height - font.lineHeight
    }

    /// Where the dot bar stops covering the page, or the top of the screen while it's away.
    private var topObstruction: CGFloat {
        if isTopBarAway { return safeTop }
        let sides = safeSides
        let placement = TopBarPlacement(safeTop: safeTop, safeSides: max(sides.left, sides.right),
                                        width: window?.bounds.width ?? bounds.width)
        return placement.top + TopBarPlacement.reach
    }

    /// Set while the dot bar is up out of the way of the keys, on a phone on its side. The page's
    /// room under it goes and comes back with it, the text staying where it is, unless the page is
    /// at its top, where it stays.
    var isTopBarAway = false {
        didSet {
            guard isTopBarAway != oldValue else { return }
            textStaysPut = contentOffset.y > -contentInset.top + 0.5
            updateInsets()
            textStaysPut = false
        }
    }
    /// Set while the top inset changes for the dot bar going or coming back (see `isTopBarAway`).
    private var textStaysPut = false

    private var bottomObstruction: CGFloat {
        max(keyboardOverlap, safeBottom)
    }

    /// Whether an input method is still composing text (marked text).
    var isComposing: Bool {
        markedTextRange != nil
    }

    /// Spelling is checked only if Settings says so, and never in code.
    private var checkedSpelling: UITextSpellCheckingType {
        Preferences.checksSpelling && !isTypingCode ? .yes : .no
    }

    @objc private func preferencesDidChange() {
        guard spellCheckingType != checkedSpelling else { return }
        spellCheckingType = checkedSpelling
        if isFirstResponder, markedTextRange == nil { reloadInputViews() }
    }

    /// Code is typed as it is: no curly quotes, capitals or spelling marks. The keyboard only
    /// picks up the change when told to, so it's told only when the caret moves into code or out.
    var isTypingCode = false {
        didSet {
            guard isTypingCode != oldValue else { return }
            spellCheckingType = checkedSpelling
            smartQuotesType = isTypingCode ? .no : .default
            autocapitalizationType = isTypingCode ? .none : .sentences
            if isFirstResponder, markedTextRange == nil { reloadInputViews() }
        }
    }

    // MARK: Editing hooks



    override func deleteBackward() {
        if markedTextRange == nil, editor?.handleBackspace() == true { return }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        guard let editor, let text = Clipboard.textToPaste else {
            super.paste(sender)
            return
        }
        editor.paste(text)
    }

    override func copy(_ sender: Any?) {
        guard let editor else {
            super.copy(sender)
            return
        }
        editor.copySelection()
    }

    override func cut(_ sender: Any?) {
        guard let editor else {
            super.cut(sender)
            return
        }
        editor.copySelection()
        // Ask the delegate first, as the keyboard does, so a cut across lines is handled like any
        // other deletion (the joined line keeps the first line's kind).
        if editor.textView(self, shouldChangeTextIn: selectedRange, replacementText: "") {
            super.deleteBackward()
        }
    }

    override func toggleBoldface(_ sender: Any?) {
        editor?.perform(.bold)
    }

    override func toggleItalics(_ sender: Any?) {
        editor?.perform(.italic)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleBoldface(_:)) || action == #selector(toggleItalics(_:)) {
            // From the keyboard, ⌘B and ⌘I also work at the caret, for what's typed next, as in
            // Notion. The edit menu offers them only for a selection.
            return selectedRange.length > 0 || sender is UIKeyCommand
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override var keyCommands: [UIKeyCommand]? {
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLine))
        outdent.wantsPriorityOverSystemBehavior = true
        // Notion's shortcuts for the styles the system has none for.
        let strikethrough = UIKeyCommand(title: "Strikethrough", action: #selector(toggleStrikethrough),
                                         input: "s", modifierFlags: [.command, .shift])
        let code = UIKeyCommand(title: "Code", action: #selector(toggleCode), input: "e", modifierFlags: .command)
        return (super.keyCommands ?? []) + [outdent, strikethrough, code]
    }

    @objc private func outdentLine() {
        editor?.perform(.outdent)
    }

    @objc private func toggleStrikethrough() {
        editor?.perform(.strikethrough)
    }

    @objc private func toggleCode() {
        editor?.toggleInline(.code)
    }

    // MARK: Code blocks

    /// Code block backgrounds, one rounded shape per block, under the text and the selection.
    /// Painted line by line, the see-through backgrounds of two lines landed on different
    /// fractions of a pixel in each line's layer and left a thin line where they met.
    private let codeBackgrounds = CALayer()
    var codeBackgroundColor: UIColor = .clear {
        didSet { setNeedsLayout() }
    }

    /// The code blocks on screen. A block that runs on past the screen is drawn on a screen's
    /// height further, square there, so its rounded end never shows early.
    private func updateCodeBackgrounds() {
        if layer.sublayers?.first !== codeBackgrounds {
            layer.insertSublayer(codeBackgrounds, at: 0)
        }
        var blocks: [(frame: CGRect, roundTop: Bool, roundBottom: Bool)] = []
        var open: (frame: CGRect, roundTop: Bool)?
        forEachLineOnScreen { fragment in
            guard let line = fragment as? BlockLayoutFragment, line.block.kind == .code else { return true }
            var frame = line.codeBackgroundFrame
            if let block = open {
                frame = block.frame.union(frame)
            } else if !line.runPosition.isFirst {
                frame.origin.y -= bounds.height
                frame.size.height += bounds.height
            }
            let roundTop = open?.roundTop ?? line.runPosition.isFirst
            if line.runPosition.isLast {
                blocks.append((frame, roundTop, true))
                open = nil
            } else {
                open = (frame, roundTop)
            }
            return true
        }
        if let block = open {
            blocks.append((CGRect(x: block.frame.minX, y: block.frame.minY, width: block.frame.width,
                                  height: block.frame.height + bounds.height), block.roundTop, false))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let color = codeBackgroundColor.resolvedColor(with: traitCollection).cgColor
        var shapes = (codeBackgrounds.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        while shapes.count < blocks.count {
            let shape = CAShapeLayer()
            codeBackgrounds.addSublayer(shape)
            shapes.append(shape)
        }
        for (index, shape) in shapes.enumerated() {
            guard index < blocks.count else {
                shape.isHidden = true
                continue
            }
            let block = blocks[index]
            let frame = block.frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
            shape.isHidden = false
            shape.fillColor = color
            shape.path = BlockLayoutFragment.roundedPath(frame, radius: 10, roundTop: block.roundTop, roundBottom: block.roundBottom)
        }
        CATransaction.commit()
    }

    // MARK: Line marks

    /// The marks beside the lines, bullets, numbers, checkboxes, quote bars and dividers, each in
    /// a layer of its own over the code backgrounds. Drawn by their own lines, as on the Mac, they
    /// went whenever UIKit took a line's view away: Writing Tools does while it rewrites a line,
    /// and shows only the line's text meanwhile, so a to-do lost its checkbox for seconds.
    private let lineMarks = CALayer()
    /// The layers showing marks, by the line each shows. A line keeps its layer while it's on
    /// screen, so scrolling only moves them; a line laid out again gets a fresh drawing.
    private var markLayers: [ObjectIdentifier: LineMarkLayer] = [:]
    private var spareMarkLayers: [LineMarkLayer] = []

    private func updateLineMarks() {
        if lineMarks.superlayer !== layer {
            layer.insertSublayer(lineMarks, above: codeBackgrounds)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var shown: [ObjectIdentifier: LineMarkLayer] = [:]
        forEachLineOnScreen { fragment in
            guard let line = fragment as? BlockLayoutFragment, let frame = line.markFrame else { return true }
            let id = ObjectIdentifier(line)
            let mark = markLayers.removeValue(forKey: id) ?? spareMarkLayers.popLast() ?? newMarkLayer()
            mark.show(line, at: frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top), traits: traitCollection)
            shown[id] = mark
            return true
        }
        for mark in markLayers.values {
            mark.clear()
            spareMarkLayers.append(mark)
        }
        markLayers = shown
        CATransaction.commit()
    }

    private func newMarkLayer() -> LineMarkLayer {
        let mark = LineMarkLayer()
        mark.isHidden = true
        lineMarks.addSublayer(mark)
        return mark
    }

    /// The lines on screen, top to bottom, until `body` returns false. UIKit lays out what's on
    /// screen, after `super.layoutSubviews()`. Most lines past that have no layout yet and lie at
    /// the top of the page: a code block further down was drawn there, over the first line. And
    /// asked for the line at a point past the last one, TextKit guesses at the layout there, and
    /// on the Mac it once never returned. So it's only asked about the top of the screen, within
    /// the text.
    private func forEachLineOnScreen(_ body: (NSTextLayoutFragment) -> Bool) {
        guard let layoutManager = textLayoutManager else { return }
        let textHeight = layoutManager.usageBoundsForTextContainer.maxY
        let top = min(max(0, contentOffset.y - textContainerInset.top), max(0, textHeight - 1))
        let bottom = contentOffset.y - textContainerInset.top + bounds.height
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 1, y: top))?.rangeInElement.location
        layoutManager.enumerateTextLayoutFragments(from: start ?? layoutManager.documentRange.location, options: []) { fragment in
            fragment.state != .none && fragment.layoutFragmentFrame.minY < bottom && body(fragment)
        }
    }

    #if DEBUG
    /// Stands in for UIKit's own, which only a finger sets off.
    var isDeceleratingForTesting: Bool?

    override var isDecelerating: Bool {
        isDeceleratingForTesting ?? super.isDecelerating
    }

    /// Where the lines' marks are drawn, top to bottom, in the view's coordinates.
    var lineMarkFramesForTesting: [CGRect] {
        markLayers.values.map(\.frame).sorted { $0.minY < $1.minY }
    }

    /// The layers drawing the lines' marks, shown or spare.
    var lineMarkLayersForTesting: [CALayer] {
        lineMarks.sublayers ?? []
    }

    /// The lines' marks alone, over nothing, as they're drawn in `rect` of the view.
    func lineMarksImageForTesting(of rect: CGRect) -> UIImage {
        markLayers.values.forEach { $0.displayIfNeeded() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            lineMarks.render(in: context.cgContext)
        }
    }

    /// The code blocks' backgrounds as drawn, in the view's coordinates.
    var codeBackgroundsForTesting: [CGRect] {
        (codeBackgrounds.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.filter { !$0.isHidden }.compactMap { $0.path?.boundingBox }
    }
    #endif

    // MARK: Selection

    /// UIKit's highlight runs from the left edge on every line a selection passes through, over
    /// bullets, numbers, checkboxes and the quote bar. Those are drawn rather than typed, so it
    /// leaves them a notch: beside the marker it starts where the text does. The notch is only as
    /// tall as the marker or bar, and runs on through the gap to a neighbouring line that has one
    /// too; UIKit counts the spacing above a line as part of its row, so cutting the whole row
    /// made the notch reach above a quote's bar but not below it. The right edge stays straight.
    /// The rectangle holding the start, where the start handle sits, begins in the text already.
    /// Below a start partway along its line, nothing left of it is lit above the next line's text:
    /// UIKit's row there took in the spacing above it from the left edge, a strip under the part
    /// of the first line not selected, and beside a checkbox the room above it did too.
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let rects = super.selectionRects(for: beforeFinalNewline(range))
        guard let layoutManager = textLayoutManager else { return rects }
        let start = rects.first(where: \.containsStart)?.rect
        var textTop: CGFloat?
        // Where the next line's text is, below the spacing UIKit counts as part of its row: the
        // line after the start's in its paragraph, or the next paragraph's first.
        if let start, start.minX > textContainerInset.left + 0.5, rects.contains(where: { $0.rect.minY >= start.maxY - 0.5 }),
           let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: offset(from: beginningOfDocument, to: range.start)),
           let fragment = layoutManager.textLayoutFragment(for: location) {
            let inFragment = contentStorage.offset(from: fragment.rangeInElement.location, to: location)
            let lines = fragment.textLineFragments
            let index = lines.firstIndex { NSLocationInRange(inFragment, $0.characterRange) } ?? lines.count - 1
            if index + 1 < lines.count {
                textTop = fragment.layoutFragmentFrame.minY + lines[index + 1].typographicBounds.minY + textContainerInset.top
            } else if let next = layoutManager.textLayoutFragment(for: fragment.rangeInElement.endLocation), next !== fragment,
                      let line = next.textLineFragments.first {
                textTop = next.layoutFragmentFrame.minY + line.typographicBounds.minY + textContainerInset.top
            }
        }
        let notched = rects.flatMap { selectionRect -> [UITextSelectionRect] in
            let rect = selectionRect.rect
            guard !rect.isNull, !rect.isEmpty, !selectionRect.containsStart,
                  let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 1, y: rect.midY - textContainerInset.top)) as? BlockLayoutFragment,
                  let textStart = fragment.textStartAfterMarker.map({ $0 + textContainerInset.left }),
                  rect.minX < textStart else { return [selectionRect] }
            let line = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            let span = fragment.markerSpan
            let top = hasMarker(lineBefore: line) ? rect.minY : max(rect.minY, span.minY + textContainerInset.top)
            let bottom = hasMarker(lineAfter: line) ? rect.maxY : min(rect.maxY, span.maxY + textContainerInset.top)
            // The row below the start: what's lit above its marker counts as above its text.
            if let start, let current = textTop, abs(rect.minY - start.maxY) < 1, !hasMarker(lineBefore: line) {
                textTop = max(current, span.minY + textContainerInset.top)
            }
            var parts: [UITextSelectionRect] = []
            if top > rect.minY {
                parts.append(SelectionRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: top - rect.minY), like: selectionRect, holdsEnd: false))
            }
            if bottom > top, rect.maxX > textStart {
                parts.append(SelectionRect(CGRect(x: textStart, y: top, width: rect.maxX - textStart, height: bottom - top), like: selectionRect))
            }
            if rect.maxY > bottom {
                parts.append(SelectionRect(CGRect(x: rect.minX, y: bottom, width: rect.width, height: rect.maxY - bottom), like: selectionRect, holdsEnd: false))
            }
            return parts
        }
        guard let start, let textTop else { return notched }
        return notched.flatMap { selectionRect -> [UITextSelectionRect] in
            let rect = selectionRect.rect
            guard !selectionRect.containsStart, rect.minX < start.minX, rect.minY < textTop else { return [selectionRect] }
            var pieces: [UITextSelectionRect] = []
            let left = max(rect.minX, start.minX)
            if rect.maxX > left {
                pieces.append(SelectionRect(CGRect(x: left, y: rect.minY, width: rect.maxX - left, height: min(rect.maxY, textTop) - rect.minY),
                                            like: selectionRect, holdsEnd: rect.maxY <= textTop))
            }
            if rect.maxY > textTop {
                pieces.append(SelectionRect(CGRect(x: rect.minX, y: textTop, width: rect.width, height: rect.maxY - textTop), like: selectionRect))
            }
            return pieces
        }
    }

    /// Whether the line before, or after, the one starting at `location` has a marker or bar of
    /// its own (a list item or a quote).
    private func hasMarker(lineBefore location: Int) -> Bool {
        location > 0 && hasMarker(at: (textStorage.string as NSString).paragraphRange(for: NSRange(location: location - 1, length: 0)).location)
    }

    private func hasMarker(lineAfter location: Int) -> Bool {
        let next = NSMaxRange((textStorage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0)))
        return next < textStorage.length && hasMarker(at: next)
    }

    private func hasMarker(at location: Int) -> Bool {
        let kind = BlockAttributes(textStorage.attributes(at: location, effectiveRange: nil)).kind
        return kind.isList || kind == .quote
    }

    // MARK: Touches

    /// TextKit 2 keeps a plain container view over the text. Touches that land on it never reach
    /// UITextView's own tap handling, so a quick tap on the text didn't start editing (only taps
    /// below the last line did). Nothing inside needs touches of its own, so the text view takes them.
    /// It's also where a touch going down is seen first, before any of the taps have it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event) else { return nil }
        guard view.isDescendant(of: self) else { return view }
        if event?.type == .touches { touchGoesDown(at: point) }
        return self
    }

    /// A touch going down on a checkbox or a link is for this view's own taps. UIKit's taps on
    /// text give way there when they ask (`gestureRecognizerShouldBegin`), but its tap counting
    /// asks only on a run's first tap: for 0.35 s after a tap it waits for the next, and takes it
    /// unasked, wherever it lands, putting the caret there and keeping any other tap from being
    /// recognised. A link tapped just after a tap on the page, as when that tap put the link card
    /// away, got the caret in it and no card (user, 2026-10-05). The run is cut short as the touch
    /// comes, before UIKit's taps have it: they take it as a first tap, and ask.
    private func touchGoesDown(at point: CGPoint) {
        guard todoLocation(at: point) != nil || tapsLink(at: point) else { return }
        for recognizer in gestureRecognizers ?? [] where recognizer !== linkTap && recognizer !== checkboxTap && Self.isTap(recognizer) && recognizer.isEnabled {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    // MARK: Checkboxes

    /// The start of the to-do line whose checkbox is under `point`, if any. A touch is always on
    /// screen, so the line is looked for among those (see `forEachLineOnScreen`).
    func todoLocation(at point: CGPoint) -> Int? {
        let containerPoint = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        var line: BlockLayoutFragment?
        forEachLineOnScreen { fragment in
            guard fragment.layoutFragmentFrame.minY <= containerPoint.y else { return false }
            if containerPoint.y < fragment.layoutFragmentFrame.maxY {
                line = fragment as? BlockLayoutFragment
                return false
            }
            return true
        }
        guard let line, line.block.kind == .todo,
              line.checkboxFrame.insetBy(dx: -12, dy: -9).contains(containerPoint) else { return nil }
        return contentStorage.offset(from: contentStorage.documentRange.location, to: line.rangeInElement.location)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let point = gestureRecognizer.location(in: self)
        let onCheckbox = todoLocation(at: point) != nil
        if gestureRecognizer === checkboxTap { return onCheckbox }
        if gestureRecognizer === linkTap { return !onCheckbox && tapsLink(at: point) }
        // Tapping a checkbox shouldn't move the caret or bring up the keyboard.
        if onCheckbox, !(gestureRecognizer is UIPanGestureRecognizer) { return false }
        // Nor should tapping a link. Holding one down still puts the caret in its text.
        if Self.isTap(gestureRecognizer), tapsLink(at: point) { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    // MARK: Links

    /// Whether `recognizer` is one of the text's taps, which a tap on a link is not: UIKit's taps
    /// on text aren't all `UITapGestureRecognizer`s. Its tap counting, `UITextMultiTapRecognizer`,
    /// and its tap-then-drag, `UITapAndAHalfRecognizer`, aren't; let through, they put the caret
    /// in a link tapped, and the link's card didn't come (see also `touchGoesDown`).
    static func isTap(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer is UITapGestureRecognizer { return true }
        let name = NSStringFromClass(type(of: recognizer))
        return name.contains("MultiTap") || name.contains("TapAndAHalf")
    }

    /// A link's text reads as text, and a double tap goes into the page to edit it, so VoiceOver
    /// opens the page's links from its actions.
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            let links = (editor?.links() ?? []).prefix(20)
            let opens = links.map { link in
                UIAccessibilityCustomAction(name: "Open \(link.text)") { [weak self] _ in
                    self?.editor?.openLink(at: link.range.location)
                    return true
                }
            }
            return (super.accessibilityCustomActions ?? []) + opens
        }
        set { super.accessibilityCustomActions = newValue }
    }

    /// Whether a tap at `point` is a link's: it opens the link, or, while the page is being edited,
    /// changes it in the format bar on the keys. With no bar there, as with a hardware keyboard, a
    /// link's text is text on a page being edited, and a tap puts the caret in it.
    private func tapsLink(at point: CGPoint) -> Bool {
        if isBeingEdited, editor?.canEditLinkInBar() != true { return false }
        return linkLocation(at: point) != nil
    }

    /// The page has the keys, or they've moved over to one of its links in the format bar.
    private var isBeingEdited: Bool {
        isFirstResponder || FormatBar.shared.isEditingLink && FormatBar.shared.editor?.textView === self
    }

    /// Where the text of a link under `point` is, if there's one there: on its letters, not just
    /// on the line beside them.
    func linkLocation(at point: CGPoint) -> Int? {
        guard let editor, let position = closestPosition(to: point) else { return nil }
        let offset = offset(from: beginningOfDocument, to: position)
        for location in [offset, offset - 1] {
            guard let link = editor.link(at: location) else { continue }
            if textFrames(of: link.range).contains(where: { $0.insetBy(dx: -2, dy: -3).contains(point) }) {
                return location
            }
        }
        return nil
    }

    /// Where the characters in `range` are drawn, a frame for each line they're on.
    private func textFrames(of range: NSRange) -> [CGRect] {
        guard let layoutManager = textLayoutManager,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        // Laid out, as text on screen is: elsewhere TextKit may only have estimated where it goes.
        layoutManager.ensureLayout(for: textRange)
        var frames: [CGRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top))
            return true
        }
        return frames
    }

    @objc private func handleLinkTap(_ recognizer: UITapGestureRecognizer) {
        tapLink(at: recognizer.location(in: self))
    }

    private func tapLink(at point: CGPoint) {
        guard let location = linkLocation(at: point) else { return }
        if isBeingEdited {
            editor?.editLink(at: location)
        } else {
            editor?.openLink(at: location)
        }
    }

    /// Lights the text a link is being changed for in the format bar, as the selection lit it: the
    /// selection goes with the keys when they move over to the link. A new link at the caret shows
    /// a caret there, where it goes. It's scrolled into view above the bar, as the caret is while
    /// typing. Nil puts it out. A layer under the text, as the code backgrounds are: TextKit's
    /// rendering attributes, made for this, didn't show.
    func showLinkTarget(_ range: NSRange?) {
        if linkTarget.superlayer !== layer { layer.insertSublayer(linkTarget, at: 0) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let range, NSMaxRange(range) < textStorage.length else {
            linkTargetRange = nil
            linkTarget.path = nil
            return
        }
        linkTargetRange = range
        let frames: [CGRect]
        let path = UIBezierPath()
        if range.length == 0 {
            guard let position = position(from: beginningOfDocument, offset: range.location) else { return }
            let caret = caretRect(for: position)
            frames = [caret]
            path.append(UIBezierPath(roundedRect: caret, cornerRadius: caret.width / 2))
            linkTarget.fillColor = tintColor.resolvedColor(with: traitCollection).cgColor
        } else {
            frames = textFrames(of: range)
            for frame in frames {
                path.append(UIBezierPath(roundedRect: frame, cornerRadius: 2))
            }
            linkTarget.fillColor = PlatformColor.adaptive(tintColor, alpha: 0.22, darkAlpha: 0.32).resolvedColor(with: traitCollection).cgColor
        }
        linkTarget.path = path.cgPath
        reveal(frames)
    }

    /// Scrolls text drawn in `frames` into view, between the dot bar and the format bar: below
    /// the bar, a little clear of it, and its first line at least, if it's taller than the room.
    private func reveal(_ frames: [CGRect]) {
        guard let first = frames.first, !isTracking, !isDragging, !isDecelerating else { return }
        let text = frames.reduce(first) { $0.union($1) }
        var target = max(contentOffset.y, text.maxY + 16 - (bounds.height - bottomObstruction))
        target = min(target, text.minY - 8 - topObstruction)
        let maxOffset = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        target = min(max(target, -contentInset.top), maxOffset)
        guard abs(target - contentOffset.y) > 0.5 else { return }
        setContentOffset(CGPoint(x: contentOffset.x, y: target), animated: true)
    }

    private let linkTarget = CAShapeLayer()
    private var linkTargetRange: NSRange?

    // MARK: Found text

    /// Lights the text a page was opened at, from a search outside Bite (see `FoundLight`). It
    /// isn't selected: without the keys a selection doesn't show, and with them typing would
    /// replace it. The caret goes before it instead. Its moment starts once Bite is on screen:
    /// opened from Spotlight, the page is lit while Bite is still coming up.
    func showFound(_ range: NSRange) {
        let layer = foundLight.layer
        if layer.superlayer !== self.layer {
            // Over a code block's background, which stays at the bottom.
            if codeBackgrounds.superlayer === self.layer {
                self.layer.insertSublayer(layer, above: codeBackgrounds)
            } else {
                self.layer.insertSublayer(layer, at: 0)
            }
        }
        foundLight.show(range)
        drawFound()
        if window?.windowScene?.activationState == .foregroundActive { foundLight.countDown() }
    }

    func hideFound(_ fade: FoundLight.Fade = .quick) {
        foundLight.hide(fade)
    }

    /// Drawn again whenever the text is laid out, as when the phone turns.
    private func drawFound() {
        guard let range = foundLight.range, NSMaxRange(range) <= textStorage.length else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = UIBezierPath()
        for frame in textFrames(of: range) {
            path.append(UIBezierPath(roundedRect: frame, cornerRadius: 2))
        }
        foundLight.layer.path = path.cgPath
        foundLight.layer.fillColor = PlatformColor.adaptive(tintColor, alpha: 0.22, darkAlpha: 0.32).resolvedColor(with: traitCollection).cgColor
    }

    @objc private func didBecomeActive() {
        foundLight.countDown()
    }

    @objc private func didEnterBackground() {
        hideFound(.atOnce)
    }

    let foundLight = FoundLight()

    #if DEBUG
    /// The text lit as found, until its light starts to go. For tests.
    var foundForTesting: NSRange? { foundLight.range }

    /// Where the found text's light is drawn, while it's lit. For tests.
    var foundLightForTesting: CGRect? {
        foundLight.range == nil ? nil : foundLight.layer.path?.boundingBoxOfPath
    }

    /// As a finger landing on the page does. For tests.
    func touchDownForTesting() {
        touchDown.onTouchDown()
    }
    #endif

    #if DEBUG
    /// As a tap at `point` does if it's a link's. Says whether it was.
    func tapLinkForTesting(at point: CGPoint) -> Bool {
        guard tapsLink(at: point) else { return false }
        tapLink(at: point)
        return true
    }

    /// Where `range`'s text is drawn. For tests.
    func textFramesForTesting(of range: NSRange) -> [CGRect] {
        textFrames(of: range)
    }

    /// The text lit for a link being changed in the format bar, and where. For tests.
    var linkTargetForTesting: NSRange? {
        linkTarget.path == nil ? nil : linkTargetRange
    }
    #endif

    @objc private func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        tapCheckbox(at: recognizer.location(in: self))
    }

    private func tapCheckbox(at point: CGPoint) {
        guard let location = todoLocation(at: point), let isChecked = editor?.toggleTodo(at: location) else { return }
        playCheckboxHaptic(isChecked: isChecked, at: point)
    }

    /// A box clicks crisply under the finger as it's ticked, and gives softly as it's unticked.
    /// It was the lightest tap there is, either way, and easily missed.
    private lazy var tickHaptic = UIImpactFeedbackGenerator(style: .rigid, view: self)
    private lazy var untickHaptic = UIImpactFeedbackGenerator(style: .soft, view: self)

    private func playCheckboxHaptic(isChecked: Bool, at point: CGPoint) {
        guard Preferences.playsHaptics else { return }
        #if DEBUG
        checkboxHapticsForTesting.append(isChecked)
        #endif
        if isChecked {
            tickHaptic.impactOccurred(intensity: 0.9, at: point)
        } else {
            untickHaptic.impactOccurred(intensity: 0.7, at: point)
        }
    }

    /// Ready as a finger lands on a checkbox, so the click comes as it lifts and not a moment
    /// later.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if Preferences.playsHaptics, let touch = touches.first, todoLocation(at: touch.location(in: self)) != nil {
            tickHaptic.prepare()
            untickHaptic.prepare()
        }
        super.touchesBegan(touches, with: event)
    }

    /// A key on a hardware keyboard, a modifier alone aside, puts found text out, as on the Mac.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.charactersIgnoringModifiers.isEmpty == false }) { hideFound() }
        super.pressesBegan(presses, with: event)
    }

    #if DEBUG
    /// Each checkbox click played, true for a tick.
    var checkboxHapticsForTesting: [Bool] = []

    /// As a tap on the checkbox at `point` does.
    func tapCheckboxForTesting(at point: CGPoint) {
        tapCheckbox(at: point)
    }
    #endif
}

/// Says when a finger lands, whatever comes of it: a tap, a drag, a long press. It recognizes
/// nothing itself, and holds up neither the touches nor the other gestures.
private final class TouchDownRecognizer: UIGestureRecognizer {
    var onTouchDown: () -> Void = {}

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchDown()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// A selection rectangle in another place, otherwise like UIKit's own. A piece cut off above or
/// below a row doesn't hold the selection's end.
private final class SelectionRect: UITextSelectionRect {
    private let frame: CGRect
    private let source: UITextSelectionRect
    private let holdsEnd: Bool

    init(_ frame: CGRect, like source: UITextSelectionRect, holdsEnd: Bool = true) {
        self.frame = frame
        self.source = source
        self.holdsEnd = holdsEnd
        super.init()
    }

    override var rect: CGRect { frame }
    override var writingDirection: NSWritingDirection { source.writingDirection }
    override var containsStart: Bool { source.containsStart }
    override var containsEnd: Bool { holdsEnd && source.containsEnd }
    override var isVertical: Bool { source.isVertical }
}

/// Draws one line's mark, as the line would (see `BiteTextView.updateLineMarks`).
private nonisolated final class LineMarkLayer: CALayer {
    private var line: BlockLayoutFragment?
    private var traits = UITraitCollection()

    func show(_ line: BlockLayoutFragment, at frame: CGRect, traits: UITraitCollection) {
        // On whole pixels, as TextKit puts each line's own layer, with the drawing moved along:
        // at a fraction of a pixel the marks came out soft, a divider most of all.
        let scale = max(1, traits.displayScale)
        let frame = CGRect(origin: CGPoint(x: (frame.minX * scale).rounded(.down) / scale, y: (frame.minY * scale).rounded(.down) / scale), size: frame.size)
        let isNew = line !== self.line || frame.size != bounds.size
            || traits.userInterfaceStyle != self.traits.userInterfaceStyle || traits.displayScale != self.traits.displayScale
        self.line = line
        self.traits = traits
        if self.frame != frame { self.frame = frame }
        isHidden = false
        guard isNew else { return }
        contentsScale = scale
        setNeedsDisplay()
    }

    func clear() {
        line = nil
        isHidden = true
    }

    /// A mark changes on the spot. A layer passed on to another line while the page scrolled
    /// faded from the old line's mark to the new one.
    override func action(forKey event: String) -> CAAction? {
        nil
    }

    override func draw(in context: CGContext) {
        guard let line, let markFrame = line.markFrame else { return }
        let origin = CGPoint(x: line.layoutFragmentFrame.minX - markFrame.minX, y: line.layoutFragmentFrame.minY - markFrame.minY)
        // The colours as the page shows them, light or dark.
        traits.performAsCurrent {
            line.drawMark(at: origin, in: context)
        }
    }
}
