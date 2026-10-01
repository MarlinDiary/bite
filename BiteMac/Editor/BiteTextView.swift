import AppKit
import BiteKit

/// The NSTextView behind each dot on the Mac. It hands paste, copy, cut, drops and checkbox
/// clicks to its `EditorController`, and paints code blocks.
final class BiteTextView: NSTextView {
    weak var editor: EditorController?

    private let contentStorage = NSTextContentStorage()
    private let finalNewlineDelegate = FinalNewlineDelegate()
    /// The system's choice for curly quotes, which code turns off for a while.
    private let usesSmartQuotes = NSSpellChecker.isAutomaticQuoteSubstitutionEnabled

    /// Builds the TextKit 2 stack by hand, as on the phone, so the final newline shows as a
    /// space (see `FinalNewlineDelegate`).
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
        wantsLayer = true
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = false
        // Notes go down as typed, as on the phone: nothing is changed behind the writer's back.
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        inlinePredictionType = .no
        // Selecting text brought up Writing Tools' button over it, which Bite has no use for.
        writingToolsBehavior = .none
        isGrammarCheckingEnabled = false
        isContinuousSpellCheckingEnabled = Preferences.checksSpelling
        // Smart delete tidies the spaces around a deleted word and took more than it said, as on
        // the phone.
        smartInsertDeleteEnabled = false
        displaysLinkToolTips = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.lineFragmentPadding = 0
        textContainerInset = NSSize(width: 20, height: 12)
        // The highlight is drawn by the view itself (see `updateSelectionHighlight`).
        selectedTextAttributes = [.backgroundColor: NSColor.clear]
        NotificationCenter.default.addObserver(self, selector: #selector(textDidProcessEditing),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesDidChange),
                                               name: Preferences.didChange, object: nil)
    }

    /// Spelling is checked as Settings says, on every page at once.
    @objc private func preferencesDidChange() {
        let checks = Preferences.checksSpelling
        if isContinuousSpellCheckingEnabled != checks { isContinuousSpellCheckingEnabled = checks }
    }

    /// Edit > Spelling > Check Spelling While Typing is the choice in Settings, for every page.
    override func toggleContinuousSpellChecking(_ sender: Any?) {
        Preferences.checksSpelling.toggle()
    }

    /// What an input method is composing shows in the page's colour. Chinese input methods ask
    /// for an underline in the system's accent: it's drawn in the caret's colour, and any
    /// highlight one asks for in the selection's (see `inPageColour`).
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(Self.inPageColour(string, underline: insertionPointColor, highlight: selectionColor),
                            selectedRange: selectedRange, replacementRange: replacementRange)
    }

    /// `string` as an input method gave it, with its underlines in `underline`, its highlights in
    /// `highlight`, and the page's own colours for the text.
    static func inPageColour(_ string: Any, underline: NSColor, highlight: NSColor) -> Any {
        guard let text = string as? NSAttributedString else { return string }
        let recoloured = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: recoloured.length)
        recoloured.removeAttribute(.foregroundColor, range: whole)
        for (key, colour) in [(NSAttributedString.Key.underlineColor, underline), (.backgroundColor, highlight)] {
            recoloured.enumerateAttribute(key, in: whole) { value, range, _ in
                if value != nil { recoloured.addAttribute(key, value: colour, range: range) }
            }
        }
        return recoloured
    }

    /// Whether an input method is still composing text (marked text).
    var isComposing: Bool {
        hasMarkedText()
    }

    var isFirstResponder: Bool {
        window?.firstResponder === self
    }

    /// Code is typed as it is, with straight quotes.
    var isTypingCode = false {
        didSet {
            guard isTypingCode != oldValue else { return }
            isAutomaticQuoteSubstitutionEnabled = isTypingCode ? false : usesSmartQuotes
        }
    }

    private var needsCaretScroll = false

    /// Brings the caret into view once the edit is laid out. The editor's own edits, a list
    /// carried on or a shortcut, don't go through AppKit's typing, which would do it.
    func requestCaretScroll() {
        guard !needsCaretScroll else { return }
        needsCaretScroll = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            needsCaretScroll = false
            scrollRangeToVisible(selectedRange)
        }
    }

    // MARK: Selection

    /// AppKit asks its delegate about the selection only once it's final, not while a drag is still
    /// selecting. So a drag along the last line lit up the empty space past it, and a click on a
    /// divider left the caret there, until the mouse let go and the editor moved them back.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        guard let editor, ranges.count == 1 else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        let range = editor.allowedSelection(ranges[0].rangeValue)
        super.setSelectedRanges([NSValue(range: range)], affinity: affinity, stillSelecting: stillSelecting)
        updateSelectionHighlight()
    }

    /// The selection's highlight, over the code backgrounds and under the text. AppKit's ran over
    /// the bullets, numbers, checkboxes and quote bar. Beside one of those it starts where the
    /// text does, as on the phone, in a notch only as tall as the marker, and runs on through the
    /// gap to a neighbouring line only when that line has a marker too. It stays one shape, with
    /// a straight right edge.
    private let selectionHighlight = CAShapeLayer()
    var selectionColor: NSColor = .selectedTextBackgroundColor {
        didSet { updateSelectionHighlight() }
    }

    private func updateSelectionHighlight() {
        guard let layer else { return }
        // AppKit's highlight is drawn by a view of its own over this one's layers. Taken clear of
        // colour (see `configure`), it still went grey while the window wasn't key, as when the
        // panel's dragged away from the ring and another app is used.
        for view in subviews where NSStringFromClass(type(of: view)) == "_NSTextSelectionView" && view.alphaValue != 0 {
            view.alphaValue = 0
        }
        if selectionHighlight.superlayer !== layer {
            layer.insertSublayer(selectionHighlight, above: codeBackgrounds.superlayer === layer ? codeBackgrounds : nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rows = highlightRows()
        guard !rows.isEmpty else {
            selectionHighlight.path = nil
            return
        }
        let origin = textContainerOrigin
        let path = CGMutablePath()
        path.addRects(rows.map { $0.offsetBy(dx: origin.x, dy: origin.y) })
        selectionHighlight.path = path
        let color = window?.isKeyWindow == true ? selectionColor : NSColor.unemphasizedSelectedTextBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionHighlight.fillColor = color.cgColor
        }
    }

    /// The selection's rows in what TextKit has laid out, which takes in what's on screen, in
    /// text-container coordinates. A long selection laid out whole took too long. And asked for
    /// the line at a point past what it had laid out, TextKit guesses at the layout there: below
    /// the last line it once guessed forever, and the tests hung.
    private func highlightRows() -> [CGRect] {
        let selection = selectedRange
        guard selection.length > 0, let layoutManager = textLayoutManager,
              let contentStorage = layoutManager.textContentManager as? NSTextContentStorage,
              let laidOut = layoutManager.textViewportLayoutController.viewportRange,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: selection.location),
              let end = contentStorage.location(start, offsetBy: selection.length),
              let selected = NSTextRange(location: start, end: end),
              let shown = selected.intersection(laidOut), !shown.isEmpty else { return [] }
        var rows: [(frame: CGRect, location: NSTextLocation?)] = []
        layoutManager.enumerateTextSegments(in: shown, type: .selection, options: []) { range, frame, _, _ in
            rows.append((frame, range?.location))
            return true
        }
        rows.sort { $0.frame.minY < $1.frame.minY }
        let width = textContainer?.size.width ?? bounds.width
        let runsOnAbove = shown.location.compare(selected.location) == .orderedDescending
        let runsOnBelow = shown.endLocation.compare(selected.endLocation) == .orderedAscending
        func lineFrame(_ index: Int) -> CGRect? {
            rows[index].location.flatMap { layoutManager.textLayoutFragment(for: $0) }?.layoutFragmentFrame
        }
        // Where the selection starts, when that's partway along its first line.
        let partialStart = !runsOnAbove && rows.count > 1 && rows[0].frame.minX > 0.5 ? rows[0].frame.minX : nil
        for index in rows.indices {
            let row = rows[index].frame
            if index > 0 || runsOnAbove {
                // A row the selection comes into from the line above starts at the left edge, and
                // takes in the spacing between it and the row above. The first row laid out takes
                // in the spacing at the top of its line, as the row above isn't laid out.
                let above = index > 0 ? rows[index - 1].frame.maxY : lineFrame(index)?.minY ?? row.minY
                let top = min(row.minY, above)
                rows[index].frame = CGRect(x: 0, y: top, width: row.maxX, height: row.maxY - top)
            }
            if index < rows.count - 1 || runsOnBelow {
                rows[index].frame.size.width = width - rows[index].frame.minX
            }
            // And the last takes in the spacing at the bottom of its line, when the selection runs
            // on below.
            if index == rows.count - 1, runsOnBelow, let bottom = lineFrame(index)?.maxY, bottom > rows[index].frame.maxY {
                rows[index].frame.size.height = bottom - rows[index].frame.minY
            }
        }
        return rows.indices.flatMap { index in
            notched(rows[index].frame, at: rows[index].location, below: index == 1 ? partialStart : nil,
                    layoutManager: layoutManager, contentStorage: contentStorage)
        }
    }

    /// `row`, which starts at `location`, with the room beside a marker left out. Below a first row
    /// that starts at `start`, partway along its line, nothing left of `start` is lit above where
    /// this row's own text is: neither the spacing it takes in above nor the room above a marker.
    /// Lit from the left edge, they made a strip under the part of the first line not selected.
    private func notched(_ row: CGRect, at location: NSTextLocation?, below start: CGFloat?,
                         layoutManager: NSTextLayoutManager, contentStorage: NSTextContentStorage) -> [CGRect] {
        let fragment = location.flatMap { layoutManager.textLayoutFragment(for: $0) }
        var parts = [row]
        // Where the row's own text is: TextKit counts the spacing above a line as part of its row.
        var textTop = row.minY
        if let fragment, let location {
            let offset = contentStorage.offset(from: fragment.rangeInElement.location, to: location)
            let lines = fragment.textLineFragments
            if let line = lines.first(where: { NSLocationInRange(offset, $0.characterRange) }) ?? lines.first {
                textTop = max(textTop, fragment.layoutFragmentFrame.minY + line.typographicBounds.minY)
            }
        }
        if let fragment = fragment as? BlockLayoutFragment, let textStart = fragment.textStartAfterMarker, row.minX < textStart {
            let line = contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
            let span = fragment.markerSpan
            let markerAbove = hasMarker(lineBefore: line)
            let top = markerAbove ? row.minY : max(row.minY, span.minY)
            let bottom = hasMarker(lineAfter: line) ? row.maxY : min(row.maxY, span.maxY)
            parts = []
            if top > row.minY {
                parts.append(CGRect(x: row.minX, y: row.minY, width: row.width, height: top - row.minY))
            }
            if bottom > top, row.maxX > textStart {
                parts.append(CGRect(x: textStart, y: top, width: row.maxX - textStart, height: bottom - top))
            }
            if row.maxY > bottom {
                parts.append(CGRect(x: row.minX, y: bottom, width: row.width, height: row.maxY - bottom))
            }
            if !markerAbove { textTop = max(textTop, span.minY) }
        }
        guard let start else { return parts }
        return parts.flatMap { part -> [CGRect] in
            guard part.minX < start, part.minY < textTop else { return [part] }
            var pieces: [CGRect] = []
            let left = max(part.minX, start)
            if part.maxX > left {
                pieces.append(CGRect(x: left, y: part.minY, width: part.maxX - left, height: min(part.maxY, textTop) - part.minY))
            }
            if part.maxY > textTop {
                pieces.append(CGRect(x: part.minX, y: textTop, width: part.width, height: part.maxY - textTop))
            }
            return pieces
        }
    }

    /// Whether the line before, or after, the one starting at `location` has a marker or bar of
    /// its own (a list item or a quote).
    private func hasMarker(lineBefore location: Int) -> Bool {
        guard let textStorage, location > 0 else { return false }
        return hasMarker(at: (textStorage.string as NSString).paragraphRange(for: NSRange(location: location - 1, length: 0)).location)
    }

    private func hasMarker(lineAfter location: Int) -> Bool {
        guard let textStorage else { return false }
        let next = NSMaxRange((textStorage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0)))
        return next < textStorage.length && hasMarker(at: next)
    }

    private func hasMarker(at location: Int) -> Bool {
        guard let textStorage else { return false }
        let kind = BlockAttributes(textStorage.attributes(at: location, effectiveRange: nil)).kind
        return kind.isList || kind == .quote
    }

    #if DEBUG
    /// The selection's highlight as drawn, in the view's coordinates.
    var selectionHighlightForTesting: CGRect? {
        selectionHighlight.path?.boundingBox
    }

    /// Whether the selection's highlight takes in `point`, in the view's coordinates.
    func selectionHighlightContainsForTesting(_ point: CGPoint) -> Bool {
        selectionHighlight.path?.contains(point) ?? false
    }

    /// The code blocks' backgrounds as drawn, in the view's coordinates.
    var codeBackgroundsForTesting: [CGRect] {
        (codeBackgrounds.sublayers ?? []).compactMap { $0 as? CAShapeLayer }.filter { !$0.isHidden }.compactMap { $0.path?.boundingBox }
    }
    #endif

    // MARK: Editing hooks

    /// At the very start of the page there's nothing before the caret, and AppKit doesn't ask
    /// about a backspace there. The rules for a line's start still apply: a list item becomes text.
    override func deleteBackward(_ sender: Any?) {
        if !isComposing, editor?.handleBackspace() == true { return }
        super.deleteBackward(sender)
    }

    /// What an input method is still composing goes in as it stands, as on the phone, when another
    /// page or window takes over. Left marked, it went unsaved.
    override func resignFirstResponder() -> Bool {
        if hasMarkedText() {
            unmarkText()
            inputContext?.discardMarkedText()
        }
        return super.resignFirstResponder()
    }

    override func paste(_ sender: Any?) {
        guard let editor, let text = Clipboard.markdown ?? Clipboard.string else {
            super.paste(sender)
            return
        }
        editor.paste(text)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
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
        // Asks the editor first, as any deletion does, so a cut across lines joins them the way
        // the editor joins lines.
        delete(sender)
    }

    /// Esc puts the page away rather than offering completions.
    override func cancelOperation(_ sender: Any?) {
        guard let next = nextResponder, next.tryToPerform(#selector(cancelOperation(_:)), with: sender) else {
            super.cancelOperation(sender)
            return
        }
    }

    // MARK: Format menu

    @objc func toggleBold(_ sender: Any?) {
        editor?.perform(.bold)
    }

    @objc func toggleItalic(_ sender: Any?) {
        editor?.perform(.italic)
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        editor?.perform(.strikethrough)
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        editor?.toggleInline(.code)
    }

    @objc func toggleTodoList(_ sender: Any?) {
        editor?.perform(.todo)
    }

    @objc func toggleBulletedList(_ sender: Any?) {
        editor?.perform(.bullet)
    }

    @objc func toggleNumberedList(_ sender: Any?) {
        editor?.perform(.ordered)
    }

    @objc func cycleHeading(_ sender: Any?) {
        editor?.perform(.heading)
    }

    @objc func toggleQuote(_ sender: Any?) {
        editor?.perform(.quote)
    }

    @objc func toggleCodeBlock(_ sender: Any?) {
        editor?.perform(.code)
    }

    @objc func indentLines(_ sender: Any?) {
        editor?.perform(.indent)
    }

    @objc func outdentLines(_ sender: Any?) {
        editor?.perform(.outdent)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let styles: [Selector: InlineStyle] = [
            #selector(toggleBold(_:)): .bold,
            #selector(toggleItalic(_:)): .italic,
            #selector(toggleStrikethrough(_:)): .strikethrough,
            #selector(toggleInlineCode(_:)): .code,
        ]
        if let action = menuItem.action, let style = styles[action] {
            menuItem.state = editor?.activeStyles.contains(style) == true ? .on : .off
            return isEditable
        }
        return super.validateMenuItem(menuItem)
    }

    // MARK: Dragging

    /// Text dragged within a page would be moved by AppKit straight in the text storage, out of
    /// the editor's hands. It isn't dragged at all: a press in the selection places the caret.
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool {
        false
    }

    /// Text dropped from elsewhere goes in as a paste where it's dropped, Markdown and all.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let editor, sender.draggingSource as? NSTextView !== self,
              let text = sender.draggingPasteboard.string(forType: .string) else { return super.performDragOperation(sender) }
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        let end = max(0, (textStorage?.length ?? 1) - 1)
        selectedRange = NSRange(location: min(index, end), length: 0)
        editor.paste(text)
        return true
    }

    // MARK: Checkboxes

    /// The start of the to-do line whose checkbox is under `point`, if any. The line is looked for
    /// among those laid out, which a click or the pointer is always over (see `highlightRows`).
    func todoLocation(at point: NSPoint) -> Int? {
        guard let contentStorage = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let origin = textContainerOrigin
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        var line: BlockLayoutFragment?
        forEachLaidOutFragment { fragment in
            guard fragment.layoutFragmentFrame.minY <= containerPoint.y else { return false }
            if containerPoint.y < fragment.layoutFragmentFrame.maxY {
                line = fragment as? BlockLayoutFragment
                return false
            }
            return true
        }
        guard let line, line.block.kind == .todo,
              line.checkboxFrame.insetBy(dx: -5, dy: -4).contains(containerPoint) else { return nil }
        return contentStorage.offset(from: contentStorage.documentRange.location, to: line.rangeInElement.location)
    }

    /// The lines TextKit has laid out, top to bottom, until `body` returns false.
    private func forEachLaidOutFragment(_ body: (NSTextLayoutFragment) -> Bool) {
        guard let layoutManager = textLayoutManager, let laidOut = layoutManager.textViewportLayoutController.viewportRange,
              laidOut.location.compare(layoutManager.documentRange.endLocation) == .orderedAscending else { return }
        layoutManager.enumerateTextLayoutFragments(from: laidOut.location, options: []) { fragment in
            fragment.rangeInElement.location.compare(laidOut.endLocation) == .orderedAscending && body(fragment)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let location = todoLocation(at: point) {
            editor?.toggleTodo(at: location)
            return
        }
        if isBelowText(point), !hasMarkedText(), !event.modifierFlags.contains(.control) {
            selectFromEnd(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    /// Below the last line, where TextKit finds no text, AppKit did nothing with a press: the caret
    /// stayed put, and a drag up into the text only moved it, selecting nothing. As in any Mac text
    /// view, the press puts the caret at the end, a drag selects from there, and with Shift held
    /// the selection runs on to the end.
    private func selectFromEnd(with event: NSEvent) {
        guard let editor else { return }
        window?.makeFirstResponder(self)
        let end = editor.allowedSelection(NSRange(location: (string as NSString).length, length: 0)).location
        let anchor = event.modifierFlags.contains(.shift) ? selectedRange().location : end
        var index = end
        select(from: anchor, to: end, stillSelecting: true)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            index = dragIndex(at: convert(next.locationInWindow, from: nil), end: end) ?? index
            let isUp = next.type == .leftMouseUp
            select(from: anchor, to: index, stillSelecting: !isUp)
            if isUp { break }
            autoscroll(with: next)
        }
    }

    /// Where a drag at `point` reaches, as AppKit's own drags do: above the page the start, below
    /// the text the end, and between the page's top and the first line, that line. TextKit finds
    /// nothing above the first line, and the drag let go of its selection there. Below the text
    /// it isn't asked at all, as a point query there once didn't come back.
    private func dragIndex(at point: NSPoint, end: Int) -> Int? {
        if point.y < 0 { return 0 }
        if isBelowText(point) { return end }
        var top = point.y
        if let layoutManager = textLayoutManager {
            layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                top = max(point.y, fragment.layoutFragmentFrame.minY + textContainerOrigin.y + 1)
                return false
            }
        }
        let index = characterIndexForInsertion(at: NSPoint(x: point.x, y: top))
        return index == NSNotFound ? nil : index
    }

    private func select(from anchor: Int, to index: Int, stillSelecting: Bool) {
        let range = NSRange(location: min(anchor, index), length: abs(index - anchor))
        setSelectedRanges([NSValue(range: range)], affinity: index < anchor ? .upstream : .downstream, stillSelecting: stillSelecting)
    }

    /// Whether `point` is below the page's last line.
    private func isBelowText(_ point: NSPoint) -> Bool {
        guard let layoutManager = textLayoutManager else { return false }
        var bottom: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation,
                                                   options: [.reverse, .ensuresLayout]) { fragment in
            bottom = fragment.layoutFragmentFrame.maxY
            return false
        }
        guard let bottom else { return false }
        return point.y > bottom + textContainerOrigin.y
    }

    /// An arrow over checkboxes, which are clicked rather than typed in.
    override func mouseMoved(with event: NSEvent) {
        if todoLocation(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.arrow.set()
            return
        }
        super.mouseMoved(with: event)
    }

    // MARK: Code blocks

    /// Code block backgrounds, one rounded shape per block, under the text, as on the phone.
    private let codeBackgrounds = CALayer()
    var codeBackgroundColor: NSColor = .clear {
        didSet { updateCodeBackgrounds() }
    }

    override func layout() {
        super.layout()
        updateDecorations()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDecorations()
    }

    /// Code blocks and the selection, which TextKit's layout leaves to the text view.
    private func updateDecorations() {
        updateCodeBackgrounds()
        updateSelectionHighlight()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(visibleAreaDidChange), name: name, object: window)
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        if let clipView = superview as? NSClipView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(visibleAreaDidChange),
                                                   name: NSView.boundsDidChangeNotification, object: clipView)
        }
    }

    @objc private func visibleAreaDidChange() {
        updateDecorations()
    }

    private var needsCodeBackgrounds = false

    /// After an edit, once it's laid out.
    @objc private func textDidProcessEditing() {
        guard !needsCodeBackgrounds else { return }
        needsCodeBackgrounds = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            needsCodeBackgrounds = false
            updateDecorations()
        }
    }

    /// The code blocks in what TextKit has laid out, which takes in what's on screen. Most lines
    /// past that have no layout yet and lie at the top of the page. A block that runs on further
    /// is drawn on a screen's height past it, square there, so its rounded end never shows early.
    private func updateCodeBackgrounds() {
        guard let layer else { return }
        if layer.sublayers?.first !== codeBackgrounds {
            layer.insertSublayer(codeBackgrounds, at: 0)
        }
        let origin = textContainerOrigin
        let visible = visibleRect
        var blocks: [(frame: CGRect, roundTop: Bool, roundBottom: Bool)] = []
        var open: (frame: CGRect, roundTop: Bool)?
        forEachLaidOutFragment { fragment in
            guard let line = fragment as? BlockLayoutFragment, line.block.kind == .code else { return true }
            var frame = line.codeBackgroundFrame
            if let block = open {
                frame = block.frame.union(frame)
            } else if !line.runPosition.isFirst {
                frame.origin.y -= visible.height
                frame.size.height += visible.height
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
                                  height: block.frame.height + visible.height), block.roundTop, false))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = codeBackgroundColor.cgColor
        }
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
            let frame = block.frame.offsetBy(dx: origin.x, dy: origin.y)
            shape.isHidden = false
            shape.fillColor = color
            shape.path = BlockLayoutFragment.roundedPath(frame, radius: 10 * EditorTheme.scale, roundTop: block.roundTop,
                                                         roundBottom: block.roundBottom)
        }
        CATransaction.commit()
    }
}
