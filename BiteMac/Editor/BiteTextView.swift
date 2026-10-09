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
        // Its width is the column's, set as the view's changes (see `setFrameSize`).
        container.widthTracksTextView = false
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
        textContainerInset = NSSize(width: Self.sideMargin, height: 12)
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
        guard let editor, let text = Clipboard.textToPaste else {
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

    /// ⌘K: a link for the selection, or the one the caret is in, in the panel's link card; a link's
    /// text selected comes off its link, as on the phone's link button.
    @objc func addLink(_ sender: Any?) {
        editor?.perform(.link)
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
        if menuItem.action == #selector(addLink(_:)) {
            menuItem.state = editor?.isLinkSelected == true ? .on : .off
            return isEditable && editor?.canEditLink == true
        }
        return super.validateMenuItem(menuItem)
    }

    // MARK: Spelling

    /// AppKit's spelling panel floats, which put it under the panel: it comes up over it.
    override func showGuessPanel(_ sender: Any?) {
        #if !SHARE_EXTENSION
        NSSpellChecker.shared.spellingPanel.level = PanelController.levelAbove
        #endif
        super.showGuessPanel(sender)
    }

    /// The text menu's Show Substitutions, over the panel too.
    override func orderFrontSubstitutionsPanel(_ sender: Any?) {
        #if !SHARE_EXTENSION
        NSSpellChecker.shared.substitutionsPanel.level = PanelController.levelAbove
        #endif
        super.orderFrontSubstitutionsPanel(sender)
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
        hideFound()
        keepsEnd = false
        let point = convert(event.locationInWindow, from: nil)
        if let location = todoLocation(at: point) {
            editor?.toggleTodo(at: location)
            return
        }
        // A click on a link opens it, as in Notes, ⌘ held or not; a drag that starts on one selects
        // text, as from anywhere. The caret goes into a link's text from beside it, or from Edit.
        if event.clickCount == 1, !hasMarkedText(), !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.shift),
           let location = linkLocation(at: point) {
            while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp {
                    if linkLocation(at: convert(next.locationInWindow, from: nil)) == location {
                        editor?.openLink(at: location)
                    }
                    return
                }
                if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 3 {
                    trackSelection(from: event)
                    return
                }
            }
            return
        }
        if event.clickCount == 1, !hasMarkedText(), !event.modifierFlags.contains(.control),
           isBelowText(point) || pointOnNearerLine(point) != nil {
            trackSelection(from: event)
            return
        }
        super.mouseDown(with: event)
    }

    /// Where TextKit finds no line, AppKit did a press wrong. Below the last line it did nothing:
    /// the caret stayed put, and a drag up into the text only moved it. Between two paragraphs, in
    /// the half nearer the one above, it put the caret at the end of that line, wherever along it
    /// the press was. Here, as in any Mac text view, the press puts the caret at the end below the
    /// text and in the nearer line between paragraphs, a drag selects from there, and with Shift
    /// held the selection runs on to it.
    private func trackSelection(from event: NSEvent) {
        guard let editor else { return }
        window?.makeFirstResponder(self)
        let end = editor.allowedSelection(NSRange(location: (string as NSString).length, length: 0)).location
        guard var index = dragIndex(at: convert(event.locationInWindow, from: nil), end: end) else { return }
        let selection = selectedRange()
        let anchor = !event.modifierFlags.contains(.shift) ? index
            : index < selection.location ? NSMaxRange(selection) : selection.location
        select(from: anchor, to: index, stillSelecting: true)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            index = dragIndex(at: convert(next.locationInWindow, from: nil), end: end) ?? index
            let isUp = next.type == .leftMouseUp
            select(from: anchor, to: index, stillSelecting: !isUp)
            if isUp { break }
            autoscroll(with: next)
        }
    }

    /// Where a press or drag at `point` reaches, as AppKit's own drags do: above the page the
    /// start, below the text the end, between paragraphs the nearer line, and between the page's
    /// top and the first line, that line. TextKit finds nothing above the first line, and a drag
    /// let go of its selection there. Below the text it isn't asked at all, as a point query there
    /// once didn't come back.
    private func dragIndex(at point: NSPoint, end: Int) -> Int? {
        if point.y < 0 { return 0 }
        if isBelowText(point) { return end }
        var target = pointOnNearerLine(point) ?? point
        if let layoutManager = textLayoutManager {
            layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                target.y = max(target.y, fragment.layoutFragmentFrame.minY + textContainerOrigin.y + 1)
                return false
            }
        }
        let index = characterIndexForInsertion(at: target)
        return index == NSNotFound ? nil : index
    }

    /// `point` in the spacing between two paragraphs, moved into whichever of their lines is
    /// nearer, where it was along it.
    private func pointOnNearerLine(_ point: NSPoint) -> NSPoint? {
        let y = point.y - textContainerOrigin.y
        var textBottomAbove: CGFloat?
        var nearer: CGFloat?
        forEachLaidOutFragment { fragment in
            let frame = fragment.layoutFragmentFrame
            guard let first = fragment.textLineFragments.first, let last = fragment.textLineFragments.last else { return true }
            let textTop = frame.minY + first.typographicBounds.minY
            let textBottom = frame.minY + last.typographicBounds.maxY
            if let above = textBottomAbove, y > above, y < textTop {
                nearer = y - above < textTop - y ? above - 1 : textTop + 1
                return false
            }
            if y <= textBottom { return false }
            textBottomAbove = textBottom
            return true
        }
        return nearer.map { NSPoint(x: point.x, y: $0 + textContainerOrigin.y) }
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

    /// The link under the pointer, if any, and where the pointer is, in the window, at every move
    /// over the page and as it leaves: for the pill the panel floats under a link (see
    /// `LinkBubble`), which goes as the pointer goes, unless it's on its way to the pill.
    var onLinkHover: ((EditorController.PageLink?, NSPoint) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["hover"] != nil {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: ["hover": true]))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onLinkHover?(nil, event.locationInWindow)
    }

    /// AppKit's I-beam, unless something floating on the page, the link card's shield, is under
    /// the pointer: then the pointer is its.
    override func cursorUpdate(with event: NSEvent) {
        if let hit = window?.contentView?.hitTest(event.locationInWindow), hit !== self, !hit.isDescendant(of: self) { return }
        super.cursorUpdate(with: event)
    }

    private func reportHover(at point: NSPoint?, inWindow: NSPoint) {
        let link = point.flatMap { linkLocation(at: $0) }.flatMap { editor?.link(at: $0) }
        onLinkHover?(link, inWindow)
    }

    /// An arrow over checkboxes, which are clicked rather than typed in, and a pointing hand over a
    /// link, which a click opens. Over something floating on the page, the link pill or card, the
    /// pointer is theirs.
    override func mouseMoved(with event: NSEvent) {
        if let hit = window?.contentView?.hitTest(event.locationInWindow), hit !== self, !hit.isDescendant(of: self) { return }
        let point = convert(event.locationInWindow, from: nil)
        reportHover(at: visibleRect.contains(point) ? point : nil, inWindow: event.locationInWindow)
        if todoLocation(at: point) != nil {
            NSCursor.arrow.set()
            return
        }
        if linkLocation(at: point) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }

    // MARK: Links

    /// Right-clicked on a link: what can be done with it, in place of the text's own menu. On
    /// other text, the text's own menu as Bite has it (see `NSMenu.tidied`), with Add Link… and Format on
    /// top of it: Bite shows no menu bar, and the styles were otherwise only to be had by their
    /// shortcuts.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let editor, let location = linkLocation(at: point), let link = editor.link(at: location) else {
            let menu = super.menu(for: event)?.tidied() ?? NSMenu()
            let add = NSMenuItem(title: String(localized: "Add Link…"), action: #selector(addLink(_:)), keyEquivalent: "k")
            add.target = self
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(aimed(FormatMenu.make(withLink: false)), at: 0)
            menu.insertItem(add, at: 0)
            return menu
        }
        contextLink = link
        return linkMenu(tint: NSColor(hex: DotPalette.colors[editor.dot].light))
    }

    /// `item` and those in its submenu made to act on this page, wherever the keys are.
    private func aimed(_ item: NSMenuItem) -> NSMenuItem {
        if let action = item.action, responds(to: action) { item.target = self }
        item.submenu?.items.forEach { _ = aimed($0) }
        return item
    }

    /// The link last right-clicked, which its menu's items act on.
    private var contextLink: EditorController.PageLink?

    /// A link's menu: rows of Bite's own, as the "…" menu's are.
    func linkMenu(tint: NSColor) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = MenuRow.keyboard
        let items = [
            MenuRow.item(String(localized: "Open Link"), symbol: "arrow.up.right.square", action: #selector(openContextLink), target: self, tint: tint),
            MenuRow.item(String(localized: "Edit Link…"), symbol: "pencil", action: #selector(editContextLink), target: self, tint: tint),
            MenuRow.item(String(localized: "Copy Link"), symbol: "doc.on.doc", action: #selector(copyContextLink), target: self, tint: tint),
            .separator(),
            MenuRow.item(String(localized: "Remove Link"), symbol: "link.badge.minus", action: #selector(removeContextLink), target: self, tint: tint),
        ]
        items.forEach(menu.addItem)
        return menu
    }

    @objc private func openContextLink() {
        guard let contextLink else { return }
        editor?.openLink(at: contextLink.range.location)
    }

    @objc private func editContextLink() {
        guard let contextLink else { return }
        editor?.editLink(at: contextLink.range.location)
    }

    @objc private func copyContextLink() {
        guard let contextLink else { return }
        Clipboard.string = EditorController.PageLink.url(for: contextLink.destination)?.absoluteString ?? contextLink.destination
    }

    @objc private func removeContextLink() {
        guard let contextLink else { return }
        editor?.removeLink(contextLink)
    }

    /// Where `range` is drawn, in the view, on the first line of it: a link's, to float its pill
    /// or card by. A caret for an empty range, where a new link goes.
    func anchorFrame(for range: NSRange) -> NSRect? {
        if range.length == 0 {
            let onScreen = firstRect(forCharacterRange: range, actualRange: nil)
            guard let window, onScreen.height > 0 else { return nil }
            let corner = convert(window.convertPoint(fromScreen: onScreen.origin), from: nil)
            return NSRect(x: corner.x, y: corner.y - onScreen.height, width: 2, height: onScreen.height)
        }
        return textFrames(of: range).first
    }

    /// Where the text of a link under `point` is, if there's one there: on its letters, not just
    /// on the line beside them.
    func linkLocation(at point: NSPoint) -> Int? {
        guard let editor else { return nil }
        let index = characterIndexForInsertion(at: point)
        guard index != NSNotFound else { return nil }
        for location in [index, index - 1] {
            guard let link = editor.link(at: location) else { continue }
            if textFrames(of: link.range).contains(where: { $0.insetBy(dx: -2, dy: -2).contains(point) }) {
                return location
            }
        }
        return nil
    }

    /// Lights the text a link is being changed for in the link card, as the selection lit it: the
    /// selection goes with the keys when they move over to the card. A new link at the caret shows
    /// a caret there, where it goes. It's scrolled into view. Nil puts it out. A layer under the
    /// text, as the code backgrounds are.
    func showLinkTarget(_ range: NSRange?) {
        guard let layer else { return }
        if linkTarget.superlayer !== layer {
            layer.insertSublayer(linkTarget, above: codeBackgrounds.superlayer === layer ? codeBackgrounds : nil)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let range, NSMaxRange(range) < (textStorage?.length ?? 0) else {
            linkTargetRange = nil
            linkTarget.path = nil
            return
        }
        linkTargetRange = range
        let path = CGMutablePath()
        let color: NSColor
        if range.length == 0 {
            if let caret = anchorFrame(for: range) {
                path.addRoundedRect(in: caret, cornerWidth: 1, cornerHeight: 1)
            }
            color = insertionPointColor
        } else {
            for frame in textFrames(of: range) {
                path.addRoundedRect(in: frame, cornerWidth: 2, cornerHeight: 2)
            }
            color = selectionColor
        }
        linkTarget.path = path
        effectiveAppearance.performAsCurrentDrawingAppearance {
            linkTarget.fillColor = color.cgColor
        }
        scrollRangeToVisible(range)
    }

    private let linkTarget = CAShapeLayer()
    private var linkTargetRange: NSRange?

    #if DEBUG
    /// The text lit for a link being changed in the card, and where. For tests.
    var linkTargetForTesting: NSRange? {
        linkTarget.path == nil ? nil : linkTargetRange
    }
    #endif

    // MARK: Found text

    /// Lights the text a page was opened at, from a search outside Bite (see `FoundLight`). It
    /// isn't selected, or typing would replace it: the caret goes before it. The panel is up by
    /// now, so its moment starts at once.
    func showFound(_ range: NSRange) {
        guard let layer else { return }
        let light = foundLight.layer
        if light.superlayer !== layer {
            // Over a code block's background, which stays at the bottom.
            if codeBackgrounds.superlayer === layer {
                layer.insertSublayer(light, above: codeBackgrounds)
            } else {
                layer.insertSublayer(light, at: 0)
            }
        }
        foundLight.show(range)
        drawFound()
        foundLight.countDown()
    }

    func hideFound(_ fade: FoundLight.Fade = .quick) {
        foundLight.hide(fade)
    }

    /// Drawn again whenever the text is laid out, as when the panel is resized. In the page's
    /// colour, as the selection is while the panel is key, whether it is or not.
    private func drawFound() {
        guard let range = foundLight.range, NSMaxRange(range) <= (textStorage?.length ?? 0) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = CGMutablePath()
        for frame in textFrames(of: range) {
            path.addRoundedRect(in: frame, cornerWidth: 2, cornerHeight: 2)
        }
        foundLight.layer.path = path
        effectiveAppearance.performAsCurrentDrawingAppearance {
            foundLight.layer.fillColor = selectionColor.cgColor
        }
    }

    let foundLight = FoundLight()

    override func rightMouseDown(with event: NSEvent) {
        hideFound()
        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        hideFound()
        keepsEnd = false
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        hideFound()
        keepsEnd = false
        super.keyDown(with: event)
    }

    #if DEBUG
    /// The text lit as found, until its light starts to go. For tests.
    var foundForTesting: NSRange? { foundLight.range }

    /// Where the found text's light is drawn, while it's lit. For tests.
    var foundLightForTesting: CGRect? {
        foundLight.range == nil ? nil : foundLight.layer.path?.boundingBoxOfPath
    }
    #endif

    /// Where the characters in `range` are drawn, a frame for each line they're on.
    private func textFrames(of range: NSRange) -> [CGRect] {
        guard let layoutManager = textLayoutManager,
              let contentStorage = layoutManager.textContentManager as? NSTextContentStorage,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        layoutManager.ensureLayout(for: textRange)
        let origin = textContainerOrigin
        var frames: [CGRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return frames
    }

    // MARK: Line length

    /// The text's widest: Notion's page measure, 44 of its body's ems, 660 pt at Bite's 15 pt.
    /// A panel wider than that only widens the margins, the text staying in the middle: lines run
    /// across a panel dragged out to the screen's width were too long to read (user, 2026-10-05).
    static let widestText: CGFloat = 660
    /// The margin each side of the text, at least.
    static let sideMargin: CGFloat = 20

    /// The column is as wide as the view less its margins, up to the widest, and the margins take
    /// the rest. It's set apart from the view: past the widest, a panel widened only moves the
    /// column, with nothing laid out again. Following the view, it changed by a point at every
    /// other step, as the margins were rounded, and the page was laid out again each time.
    override func setFrameSize(_ newSize: NSSize) {
        let column = min(Self.widestText, max(0, newSize.width - 2 * Self.sideMargin))
        // A new column lays the page out again, and the line at the top is put back after.
        let place = placeToPutBack == nil && textContainer.map { $0.size.width != column } == true ? placeOnScreen() : nil
        super.setFrameSize(newSize)
        if let container = textContainer, container.size.width != column {
            container.size = NSSize(width: column, height: container.size.height)
        }
        let margin = max(Self.sideMargin, ((newSize.width - column) / 2).rounded(.down))
        if textContainerInset.width != margin {
            textContainerInset = NSSize(width: margin, height: textContainerInset.height)
        }
        if let place {
            putBack(place)
        }
    }

    // MARK: Keeping the place

    /// Where the line at the top of what shows starts in the text, and how far its top is from
    /// the top of what shows, where the dot bar ends: the line as it wraps, so that the lines
    /// above it wrapping again don't move it. Kept as a count of characters: the page may change
    /// meanwhile, as another device's change comes in, and TextKit's locations with it.
    private typealias PlaceOnScreen = (character: Int, offset: CGFloat)

    /// The line to put back where it was, as the page is next laid out while it shows.
    private var placeToPutBack: PlaceOnScreen?
    /// The line at the top as a live resize began.
    private var placeAcrossLiveResize: PlaceOnScreen?

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        placeAcrossLiveResize = isHiddenOrHasHiddenAncestor ? nil : placeOnScreen()
    }

    /// AppKit keeps the first character that showed as a live resize began, and as it ends,
    /// scrolls its line's top to the top of what shows: a line partly scrolled away, as under the
    /// dot bar, came back whole as the panel's edge was let go, and the page jumped by up to a
    /// line, though nothing had changed. That line is put back as it was.
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        guard let place = placeAcrossLiveResize else { return }
        placeAcrossLiveResize = nil
        putBack(place)
    }

    /// The other dots' pages, hidden, follow the panel's width too: theirs is put back as they're
    /// shown.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        if placeToPutBack != nil || keepsEnd {
            needsLayout = true
        }
    }

    /// Another page shown: found text here is put out, to be gone when this one's back.
    override func viewDidHide() {
        super.viewDidHide()
        hideFound(.atOnce)
    }

    /// Set to keep the end of the page in view as the page is laid out and takes the panel's size,
    /// until it's clicked, scrolled or typed in: a page shared to opens at its end, where what's
    /// shared goes.
    var keepsEnd = false {
        didSet { if keepsEnd { needsLayout = true } }
    }

    /// Whether the end of the page shows: scrolled there, or the whole page in view.
    var showsEnd: Bool {
        guard let scrollView = enclosingScrollView else { return true }
        return scrollView.contentView.bounds.maxY - scrollView.contentInsets.bottom >= frame.maxY - 2
    }

    /// Scrolls to the end of the page. Laying out, the last of it is laid out where it goes first,
    /// enough to fill what shows: the end TextKit guessed at, from lines it hadn't laid out, was
    /// short of the real one, and the clip view, scrolled there, didn't stop at the page's end.
    private func scrollToEnd(layingOut: Bool = false) {
        guard let layoutManager = textLayoutManager, let scrollView = enclosingScrollView else { return }
        let document = layoutManager.documentRange
        let length = layoutManager.offset(from: document.location, to: document.endLocation)
        let start = layoutManager.location(document.endLocation, offsetBy: -min(Self.laidOutAbove, length)) ?? document.location
        var bottom: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: start, options: layingOut ? [.ensuresLayout] : []) { fragment in
            bottom = fragment.layoutFragmentFrame.maxY
            return true
        }
        guard let bottom else { return }
        let clipView = scrollView.contentView
        let end = bottom + textContainerOrigin.y + textContainerInset.height + scrollView.contentInsets.bottom - clipView.bounds.height
        let top = max(-scrollView.contentInsets.top, end)
        guard abs(clipView.bounds.minY - top) > 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: top))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Scrolls `range` into view a little below the dot bar, as at a search result picked
    /// outside Bite: where the eye goes first, with a few lines before it. In view already, it
    /// stays where it is. Scrolled as a place kept is, laid out where it goes, as TextKit's
    /// guesses at lines far down would show other text there.
    func show(_ range: NSRange) {
        guard let scrollView = enclosingScrollView, !isInView(range.location) else { return }
        let clipView = scrollView.contentView
        let visibleHeight = clipView.bounds.height - scrollView.contentInsets.top - scrollView.contentInsets.bottom
        putBack((range.location, (visibleHeight / 4).rounded()))
    }

    /// Whether the line `character` is on shows whole, below the dot bar.
    private func isInView(_ character: Int) -> Bool {
        guard let layoutManager = textLayoutManager, let scrollView = enclosingScrollView,
              let viewport = layoutManager.textViewportLayoutController.viewportRange,
              let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: character),
              viewport.contains(location), let fragment = layoutManager.textLayoutFragment(for: location) else { return false }
        let inParagraph = character - layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard let line = fragment.textLineFragments.first(where: { NSMaxRange($0.characterRange) > inParagraph })
            ?? fragment.textLineFragments.last else { return false }
        let top = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textContainerOrigin.y
        let clip = scrollView.contentView.bounds
        return top >= clip.minY + scrollView.contentInsets.top
            && top + line.typographicBounds.height <= clip.maxY - scrollView.contentInsets.bottom
    }

    private func putBack(_ place: PlaceOnScreen) {
        placeToPutBack = place
        needsLayout = true
    }

    private func placeOnScreen() -> PlaceOnScreen? {
        guard let layoutManager = textLayoutManager, let scrollView = enclosingScrollView else { return nil }
        let top = scrollView.contentView.bounds.minY + scrollView.contentInsets.top - textContainerOrigin.y
        guard let first = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, top))) else { return nil }
        let document = layoutManager.documentRange.location
        var place: PlaceOnScreen?
        var fragments = 0
        // The first line mostly below the top, a few paragraphs on at most: one above it, mostly
        // behind the bar, may wrap again without moving it.
        layoutManager.enumerateTextLayoutFragments(from: first.rangeInElement.location) { fragment in
            let frame = fragment.layoutFragmentFrame
            let paragraph = layoutManager.offset(from: document, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                place = (paragraph + line.characterRange.location, frame.minY + line.typographicBounds.minY - top)
                if frame.minY + line.typographicBounds.midY >= top { return false }
            }
            fragments += 1
            return fragments < 8
        }
        return place
    }

    /// How much of the text above the line kept is laid out with it, in characters: enough to
    /// take in what's behind the dot bar and a little more, whatever the paragraphs.
    private static let laidOutAbove = 2000

    /// Scrolls the place's line back where it was, by where it now is.
    ///
    /// Laid out again for a new width, TextKit guesses at the height of the lines not laid out
    /// yet, and AppKit, keeping what shows in place by those guesses, scrolled the page on: by a
    /// line or more at each step of the panel's edge dragged, and further each time, with nothing
    /// to show at times. `layingOut`, before AppKit lays out what shows, the line is laid out
    /// first, with a little of the text above it, behind the dot bar and past it, and what shows
    /// below it: AppKit then finds them all laid out where they're seen. Nothing further up is
    /// laid out, which on a long page took long at every step.
    private func scroll(to place: PlaceOnScreen, layingOut: Bool = false) {
        guard let layoutManager = textLayoutManager, let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let document = layoutManager.documentRange
        let length = layoutManager.offset(from: document.location, to: document.endLocation)
        let character = min(max(0, place.character), length)
        guard let location = layoutManager.location(document.location, offsetBy: character),
              let paragraph = layoutManager.textLayoutFragment(for: location)?.rangeInElement.location else { return }
        // What's above it goes first: laid out after, by AppKit, it could push the line down.
        let above = min(Self.laidOutAbove, layoutManager.offset(from: document.location, to: paragraph))
        let start = layingOut ? layoutManager.location(paragraph, offsetBy: -above) ?? paragraph : paragraph
        var lineTop: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: start, options: layingOut ? [.ensuresLayout] : []) { fragment in
            let frame = fragment.layoutFragmentFrame
            if lineTop == nil, fragment.rangeInElement.location.compare(paragraph) != .orderedAscending {
                let inParagraph = character - layoutManager.offset(from: document.location, to: fragment.rangeInElement.location)
                let line = fragment.textLineFragments.first { NSMaxRange($0.characterRange) > inParagraph } ?? fragment.textLineFragments.last
                lineTop = frame.minY + (line?.typographicBounds.minY ?? 0)
            }
            guard let lineTop else { return true }
            // On down to the bottom of what shows.
            return layingOut && frame.maxY < lineTop - place.offset - scrollView.contentInsets.top + clipView.bounds.height
        }
        guard let lineTop else { return }
        let top = lineTop + textContainerOrigin.y - place.offset - scrollView.contentInsets.top
        guard abs(clipView.bounds.minY - top) > 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: top))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: Code blocks

    /// Code block backgrounds, one rounded shape per block, under the text, as on the phone.
    private let codeBackgrounds = CALayer()
    var codeBackgroundColor: NSColor = .clear {
        didSet { updateCodeBackgrounds() }
    }

    override func layout() {
        let isShown = !isHiddenOrHasHiddenAncestor
        // Kept at its end, the page has no other place to keep.
        if isShown, keepsEnd { placeToPutBack = nil }
        let place = isShown ? placeToPutBack : nil
        if let place {
            scroll(to: place, layingOut: true)
        } else if isShown, keepsEnd {
            scrollToEnd(layingOut: true)
        }
        super.layout()
        if let place {
            placeToPutBack = nil
            // AppKit, keeping what shows in place by its own reckoning, may have moved it again.
            scroll(to: place)
        } else if isShown, keepsEnd {
            scrollToEnd()
        }
        updateDecorations()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDecorations()
    }

    /// Code blocks, the selection and found text, which TextKit's layout leaves to the text view.
    private func updateDecorations() {
        updateCodeBackgrounds()
        updateSelectionHighlight()
        drawFound()
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

extension NSMenu {
    /// A text's right-click menu without the system's menus of switches and tools Bite has no use
    /// for: Font, of fonts and colours a page can't keep; Layout Orientation, which would stand the
    /// page on its side; Spelling and Grammar, whose switch Settings has, though a misspelt word's
    /// corrections stay on top; Substitutions, which offer what Bite keeps off; Transformations;
    /// and Speech, which the system's Speak Selection does anywhere. Known by what their items do,
    /// as their titles are in the system's language.
    @discardableResult
    func tidied() -> NSMenu {
        let unwanted = [#selector(NSFontManager.orderFrontFontPanel(_:)), #selector(NSTextView.changeLayoutOrientation(_:)),
                        #selector(NSTextView.toggleContinuousSpellChecking(_:)), #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
                        #selector(NSTextView.uppercaseWord(_:)), #selector(NSTextView.startSpeaking(_:))]
        for item in items where item.submenu?.items.contains(where: { $0.action.map(unwanted.contains) == true }) == true {
            removeItem(item)
        }
        // No line at either end, or two in a row.
        var lastWasLine = true
        for item in items where !item.isHidden {
            if item.isSeparatorItem, lastWasLine { removeItem(item) }
            lastWasLine = item.isSeparatorItem
        }
        if let last = items.last(where: { !$0.isHidden }), last.isSeparatorItem { removeItem(last) }
        return self
    }
}
