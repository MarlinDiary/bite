import UIKit
import BiteKit

/// The UITextView behind each dot. It hands backspace, paste, copy and checkbox taps to its
/// `EditorController` and leaves room at the top for the dot bar.
final class BiteTextView: UITextView {
    weak var editor: EditorController?

    private let contentStorage = NSTextContentStorage()
    private let finalNewlineDelegate = FinalNewlineDelegate()
    private lazy var checkboxTap = UITapGestureRecognizer(target: self, action: #selector(handleCheckboxTap(_:)))
    /// How far below the safe area the dot bar reaches; text scrolled higher is behind it.
    private let topBarHeight: CGFloat = 50
    /// Where the first line starts, below the safe area. Leaves some air under the dot bar.
    private let topTextInset: CGFloat = 74
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
        (isFirstResponder && !isResigning) || keepsKeyboardRoom ? keyboardOverlap : 0
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
    private var isResigning = false

    private func applyKeyboardInset() {
        updateScrollIndicatorInsets()
        // Changing the inset under a finger clamps the scroll position on every frame, which made
        // the text shudder while the keyboard was dragged away. That waits for the finger to lift
        // (`dragDidEnd`), but not for the page to stop scrolling: the room a swiped-away keyboard
        // left stayed open until then, half a second too long.
        guard !isTracking, abs(insetKeyboardOverlap - wantedKeyboardOverlap) > 0.5 else { return }
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

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let keepsPlace = wasScrolledSinceReady && !isFirstResponder
        let became = super.becomeFirstResponder()
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
        // Smart delete tidies the spaces around a deleted word, and deleted more than it said it
        // would: emptying the last line of a code block took the line break with it, so the line
        // was gone and typing went into the line below.
        smartInsertDeleteType = .no
        allowsEditingTextAttributes = false
        textContainer.lineFragmentPadding = 0
        addGestureRecognizer(checkboxTap)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BiteTextView, _) in
            view.setNeedsLayout()
        }
        updateInsets()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // SwiftUI hosts this view edge to edge, so its own safe area is zero; the window's isn't.
        updateInsets()
        // Text layout has just run here too, so the code blocks can follow it in the same frame.
        updateCodeBackgrounds()
        // Text layout has just run, so the caret rect is final.
        if needsCaretScroll {
            needsCaretScroll = false
            scrollCaretIntoView(animated: true)
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
        let textInsets = UIEdgeInsets(top: topTextInset - topBarHeight, left: 22 + sides.left, bottom: bottomTextInset, right: 22 + sides.right)
        if textContainerInset != textInsets {
            textContainerInset = textInsets
        }
        let insets = UIEdgeInsets(top: topObstruction, left: 0,
                                  bottom: insetKeyboardOverlap > 0 ? insetKeyboardOverlap + typingRoom : safeBottom, right: 0)
        if contentInset != insets {
            // What's on screen stays put when the top inset first arrives or the safe area changes.
            let shift = insets.top - contentInset.top
            contentInset = insets
            if shift != 0 {
                contentOffset.y -= shift
            }
        }
        updateScrollIndicatorInsets()
    }

    /// The indicator runs from just under the dot bar down to the format bar or, with the keyboard
    /// down, to just above where the screen's corner starts to curve. UIKit's own default stops
    /// right where the curve begins, so the indicator looked cut off by the corner. Unlike the
    /// content inset it can follow a keyboard that's being swiped away, since it never moves the
    /// text.
    private func updateScrollIndicatorInsets() {
        let insets = UIEdgeInsets(top: safeTop + topBarHeight, left: 0, bottom: max(wantedKeyboardOverlap, cornerClearance), right: 0)
        if verticalScrollIndicatorInsets != insets {
            verticalScrollIndicatorInsets = insets
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
    /// if it's in view where the page is.
    private func caretScrollTarget() -> CGFloat? {
        guard let position = selectedTextRange?.end else { return nil }
        let caret = caretRect(for: position)
        guard !caret.isNull, !caret.isInfinite else { return nil }
        let visibleTop = contentOffset.y + topObstruction
        let visibleBottom = contentOffset.y + bounds.height - bottomObstruction
        let comfort = min(96, max(0, (visibleBottom - visibleTop) * 0.25))
        var target = contentOffset.y
        if caret.maxY + comfort > visibleBottom {
            // Settle a little past the threshold: an empty line's caret sits a few points higher
            // than the same line once it has text, and that shouldn't cause a second nudge.
            target += caret.maxY + comfort + 16 - visibleBottom
        } else if caret.minY - 8 < visibleTop {
            target -= visibleTop - (caret.minY - 8)
        }
        let maxOffset = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        target = min(max(target, -contentInset.top), maxOffset)
        guard abs(target - contentOffset.y) > 0.5 else { return nil }
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

    private var topObstruction: CGFloat {
        safeTop + topBarHeight
    }

    private var bottomObstruction: CGFloat {
        max(keyboardOverlap, safeBottom)
    }

    /// Code is typed as it is: no curly quotes, capitals or spelling marks. The keyboard only
    /// picks up the change when told to, so it's told only when the caret moves into code or out.
    var isTypingCode = false {
        didSet {
            guard isTypingCode != oldValue else { return }
            spellCheckingType = isTypingCode ? .no : .default
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
        guard let editor, let text = EditorController.copiedMarkdown ?? UIPasteboard.general.string else {
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

    /// The code blocks on screen, from the laid-out lines, a screen's height beyond either edge
    /// included. A block that runs on further is drawn on past that, square there, so its
    /// rounded end never shows early.
    private func updateCodeBackgrounds() {
        guard let layoutManager = textLayoutManager else { return }
        if layer.sublayers?.first !== codeBackgrounds {
            layer.insertSublayer(codeBackgrounds, at: 0)
        }
        let visibleTop = contentOffset.y - textContainerInset.top - bounds.height
        let visibleBottom = contentOffset.y - textContainerInset.top + 2 * bounds.height
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 1, y: max(0, visibleTop)))?.rangeInElement.location
        var blocks: [(frame: CGRect, roundTop: Bool, roundBottom: Bool)] = []
        var open: (frame: CGRect, roundTop: Bool)?
        layoutManager.enumerateTextLayoutFragments(from: start ?? layoutManager.documentRange.location, options: []) { fragment in
            guard fragment.layoutFragmentFrame.minY < visibleBottom else { return false }
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

    // MARK: Selection

    /// UIKit's highlight runs from the left edge on every line a selection passes through, over
    /// bullets, numbers, checkboxes and the quote bar. Those are drawn rather than typed, so it
    /// leaves them a notch: beside the marker it starts where the text does. The notch is only as
    /// tall as the marker or bar, and runs on through the gap to a neighbouring line that has one
    /// too; UIKit counts the spacing above a line as part of its row, so cutting the whole row
    /// made the notch reach above a quote's bar but not below it. The right edge stays straight.
    /// The rectangle holding the start, where the start handle sits, begins in the text already.
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        let rects = super.selectionRects(for: beforeFinalNewline(range))
        guard let layoutManager = textLayoutManager else { return rects }
        return rects.flatMap { selectionRect -> [UITextSelectionRect] in
            let rect = selectionRect.rect
            guard !rect.isNull, !rect.isEmpty, !selectionRect.containsStart,
                  let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 1, y: rect.midY - textContainerInset.top)) as? BlockLayoutFragment,
                  let textStart = fragment.textStartAfterMarker.map({ $0 + textContainerInset.left }),
                  rect.minX < textStart else { return [selectionRect] }
            let line = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            let span = fragment.markerSpan
            let top = hasMarker(lineBefore: line) ? rect.minY : max(rect.minY, span.minY + textContainerInset.top)
            let bottom = hasMarker(lineAfter: line) ? rect.maxY : min(rect.maxY, span.maxY + textContainerInset.top)
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
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event) else { return nil }
        return view.isDescendant(of: self) ? self : view
    }

    // MARK: Checkboxes

    /// The start of the to-do line whose checkbox is under `point`, if any.
    func todoLocation(at point: CGPoint) -> Int? {
        guard let layoutManager = textLayoutManager,
              let contentStorage = layoutManager.textContentManager as? NSTextContentStorage else { return nil }
        let containerPoint = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let probe = CGPoint(x: max(containerPoint.x, 1), y: containerPoint.y)
        guard let fragment = layoutManager.textLayoutFragment(for: probe) as? BlockLayoutFragment,
              fragment.block.kind == .todo,
              fragment.checkboxFrame.insetBy(dx: -12, dy: -9).contains(containerPoint) else { return nil }
        return contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let onCheckbox = todoLocation(at: gestureRecognizer.location(in: self)) != nil
        if gestureRecognizer === checkboxTap { return onCheckbox }
        // Tapping a checkbox shouldn't move the caret or bring up the keyboard.
        if onCheckbox, !(gestureRecognizer is UIPanGestureRecognizer) { return false }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc private func handleCheckboxTap(_ recognizer: UITapGestureRecognizer) {
        guard let location = todoLocation(at: recognizer.location(in: self)) else { return }
        editor?.toggleTodo(at: location)
    }
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
