#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreText
import BiteKit

#if canImport(UIKit)
typealias EditorTextViewDelegate = UITextViewDelegate & UITextDragDelegate & UITextDropDelegate
#else
typealias EditorTextViewDelegate = NSTextViewDelegate
#endif

/// Runs one dot's text view: loads Markdown into it, applies the Notion-style input rules from
/// `InputRules`, keeps the display attributes in sync and reports every change as Markdown. The
/// same code runs UIKit's text view on the phone and AppKit's on a Mac; where the two differ is
/// marked `#if canImport(UIKit)`.
final class EditorController: NSObject, EditorTextViewDelegate {
    let dot: Int
    let textView = BiteTextView()
    /// The page as Markdown, once typing pauses. Worked out off the main thread.
    var onChange: ((_ markdown: String) -> Void)?
    /// Whether the page is empty, as soon as that changes: the dot bar shows it.
    var onEmptyChange: ((_ isEmpty: Bool) -> Void)?
    #if canImport(UIKit)
    /// Whether Writing Tools is at work on the page, as it starts and once it's done: the format
    /// bar keeps out of its way.
    var onWritingToolsChange: ((_ isAtWork: Bool) -> Void)?
    /// The page has just taken the keyboard.
    var onBeginEditing: (() -> Void)?
    /// Whether a link can be changed in the format bar now (`onEditLink`): not with no keys on
    /// screen, as with a hardware keyboard, where the bar doesn't show.
    var canEditLinkInBar: () -> Bool = { false }
    #endif
    /// A link to change in the format bar: the link button's, which may be a new one to make, or
    /// one tapped while the page is being edited.
    var onEditLink: ((PageLink) -> Void)?
    /// Goes where a tapped link goes, out of the app. Tests catch it instead.
    var openURL: (URL) -> Void = { url in
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
    var loadedRevision = -1

    private let theme: EditorTheme
    private let layoutDelegate: BlockLayoutDelegate
    /// The user's edit in flight, from `shouldChange(_:to:)` until `textChanged()`.
    private var pendingEdit: PendingEdit?
    /// Inline style for the next typed character, set right after an inline shortcut fires so
    /// typing continues in plain text.
    private var typingOverride: (style: InlineStyle, location: Int)?
    private var isApplyingEdit = false
    /// Where the caret was, to tell which way it moved.
    private var lastCaretLocation = 0
    /// Set while the selection is being moved off the final newline or a divider.
    private var isMovingSelection = false

    #if canImport(UIKit)
    private var storage: NSTextStorage { textView.textStorage }
    #else
    private var storage: NSTextStorage { textView.textStorage! }
    /// Each page has its own undo, as on the phone; the window's would mix up all seven.
    private let pageUndoManager = UndoManager()
    #endif
    private var string: NSString { storage.mutableString }

    init(dot: Int, accent: PlatformColor) {
        self.dot = dot
        theme = EditorTheme(accent: accent)
        layoutDelegate = BlockLayoutDelegate(theme: theme)
        super.init()
        textView.configure()
        textView.editor = self
        textView.delegate = self
        #if canImport(UIKit)
        textView.textDragDelegate = self
        textView.textDropDelegate = self
        textView.tintColor = accent
        #else
        textView.insertionPointColor = accent
        textView.selectionColor = PlatformColor.adaptive(accent, alpha: 0.22, darkAlpha: 0.32)
        // What an input method composes with no look of its own is lit as the selection is, not in
        // AppKit's yellow, and keeps the colours of a heading or code. The Chinese ones bring their
        // own underline (see `BiteTextView.setMarkedText`).
        textView.markedTextAttributes = [.backgroundColor: textView.selectionColor]
        #endif
        textView.textLayoutManager?.delegate = layoutDelegate
        textView.codeBackgroundColor = theme.codeBackground
        // Before the text storage fixes its attributes, which stretches the edited range to whole
        // paragraphs: afterwards it no longer says where the new text is.
        NotificationCenter.default.addObserver(self, selector: #selector(storageWillProcessEditing),
                                               name: NSTextStorage.willProcessEditingNotification, object: storage)
        #if !canImport(UIKit)
        // AppKit undoes its own typing without telling the delegate. The change is put right as
        // soon as the undo is done, as on the phone, rather than a moment later.
        for name in [NSNotification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerDidChange), name: name, object: pageUndoManager)
        }
        for name in [NSNotification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoManagerWillChange), name: name, object: pageUndoManager)
        }
        #endif
    }

    func load(markdown: String) {
        // What an input method was composing goes with the text it was in. Committed as an edit,
        // it was reported after Clear had emptied the page, and the dot showed a full page.
        if textView.isComposing {
            isApplyingEdit = true
            textView.unmarkText()
            isApplyingEdit = false
        }
        pendingEdit = nil
        // And a link shown as it was being typed.
        linkPreview = nil
        // What's loaded replaces anything still waiting to be reported, say after Clear, and
        // any report still being worked out.
        pendingReport?.cancel()
        pendingReport = nil
        reportDeadline = nil
        changeCount += 1
        reportedCount = changeCount
        let text = styledText(for: MarkdownParser.parse(markdown))
        isApplyingEdit = true
        storage.setAttributedString(text)
        isApplyingEdit = false
        unannouncedEdit = nil
        reportedEmpty = pageIsEmpty
        textView.undoManager?.removeAllActions()
        // Picking up a dot means carrying on at the end. The caret goes there once the page is
        // edited: placing it at the end of a long page laid out the whole page to find where the
        // end is, which made opening the app slow.
        caretGoesToEnd = true
        if textView.isFirstResponder { focus() }
        updateTypingAttributes()
    }

    /// Set when a page is loaded, until its caret is first placed.
    private var caretGoesToEnd = false

    /// Takes in the page as another device changed it. Only the lines that differ are replaced,
    /// so the caret stays on the text it was on, and the page doesn't scroll. Undo starts over:
    /// the system's own steps for typing know only where text was, and would have taken out
    /// whatever had moved there.
    func applyRemote(markdown: String) {
        let incoming = MarkdownParser.parse(markdown).blocks
        let new = incoming.isEmpty ? [Block()] : incoming
        // Read back as Markdown first, so both sides' lines say what the parser says: a list item
        // read from the page has the number it shows, and the parser gives none past the first.
        let current = PageSnapshot(text: storage).markdown()
        guard current != markdown else { return }
        let old = MarkdownParser.parse(current).blocks
        guard old != new else { return }
        // What an input method was composing goes in as it stands, as when a page is loaded.
        if textView.isComposing {
            isApplyingEdit = true
            textView.unmarkText()
            isApplyingEdit = false
        }
        pendingEdit = nil
        typingOverride = nil
        var lines: [NSRange] = []
        var position = 0
        while position < storage.length {
            let line = lineRange(at: position)
            lines.append(line)
            position = NSMaxRange(line)
        }
        // The lines both have at the start and the end stay as they are.
        var range = NSRange(location: 0, length: storage.length)
        var replacement = styledText(for: BiteDocument(blocks: new))
        if lines.count == old.count {
            var first = 0
            while first < old.count, first < new.count, old[first] == new[first] { first += 1 }
            var oldEnd = old.count, newEnd = new.count
            while oldEnd > first, newEnd > first, old[oldEnd - 1] == new[newEnd - 1] {
                oldEnd -= 1
                newEnd -= 1
            }
            let start = first < lines.count ? lines[first].location : storage.length
            range = NSRange(location: start, length: (oldEnd > first ? NSMaxRange(lines[oldEnd - 1]) : start) - start)
            replacement = newEnd > first ? styledText(for: BiteDocument(blocks: Array(new[first..<newEnd]))) : NSMutableAttributedString()
        }
        let delta = replacement.length - range.length
        // A caret in the lines that changed stays in them, as far along as they go, before the
        // last one's line break.
        func moved(_ location: Int) -> Int {
            if location <= range.location { return location }
            if location >= NSMaxRange(range) { return location + delta }
            return min(location, range.location + max(0, replacement.length - 1))
        }
        let selection = textView.selectedRange
        // A link shown as it's typed moves along with its text, or, in the lines that changed, is
        // let go of: what came in is what was there.
        if var preview = linkPreview, NSMaxRange(preview.range) > range.location {
            if preview.range.location >= NSMaxRange(range) {
                preview.range.location += delta
                preview.selection.location = moved(preview.selection.location)
                linkPreview = preview
            } else {
                linkPreview = nil
            }
        }
        #if canImport(UIKit)
        textView.inputDelegate?.textWillChange(textView)
        #endif
        isApplyingEdit = true
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        isApplyingEdit = false
        let start = moved(selection.location)
        let moved = stepOverDivider(clamp(NSRange(location: start, length: max(0, moved(NSMaxRange(selection)) - start))))
        // The text view moves the selection along with the text itself, but not always to the
        // same place.
        if moved != textView.selectedRange {
            textView.selectedRange = moved
        }
        #if canImport(UIKit)
        textView.inputDelegate?.textDidChange(textView)
        #endif
        let changed = NSRange(location: range.location, length: replacement.length)
        ensureTrailingNewline()
        restyle(changed)
        updateStructure(around: changed)
        updateTypingAttributes()
        textView.undoManager?.removeAllActions()
        // The page now reads as the Markdown that came in: there's nothing to report back.
        pendingReport?.cancel()
        pendingReport = nil
        reportDeadline = nil
        changeCount += 1
        reportedCount = changeCount
        let isEmpty = pageIsEmpty
        if isEmpty != reportedEmpty {
            reportedEmpty = isEmpty
            onEmptyChange?(isEmpty)
        }
    }

    func focus() {
        placeCaretIfNew()
        #if canImport(UIKit)
        textView.becomeFirstResponder()
        #else
        textView.window?.makeFirstResponder(textView)
        #endif
    }

    /// Shows where `query` is on `line`, for a page opened at a search result picked outside Bite:
    /// lit, with the caret before it, and scrolled into view a little below the top if it isn't in
    /// view. Not on the line, the line is lit; with no line, the first place on the page it is.
    /// Words not found together are looked for one at a time, as Spotlight finds a line with each
    /// of them on it. Returns whether anything was found.
    @discardableResult
    func reveal(_ query: String, line: Int? = nil) -> Bool {
        let text = storage.string as NSString
        var found: NSRange?
        if let line, let lineRange = Self.range(ofLine: line, in: text) {
            found = Self.range(of: query, in: text, within: lineRange) ?? (lineRange.length > 0 ? lineRange : nil)
        }
        guard let range = found ?? Self.range(of: query, in: text, within: NSRange(location: 0, length: text.length)) else {
            return false
        }
        caretGoesToEnd = false
        let caret = NSRange(location: range.location, length: 0)
        #if canImport(UIKit)
        textView.selectedRange = caret
        #else
        textView.setSelectedRange(caret)
        #endif
        textView.show(range)
        textView.showFound(range)
        return true
    }

    /// Where `query` first is in `text` within `range`, whatever its case or accents, or else the
    /// first of its words that is there.
    static func range(of query: String, in text: NSString, within range: NSRange) -> NSRange? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        for wanted in [query] + words where !wanted.isEmpty {
            let found = text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: range)
            if found.location != NSNotFound { return found }
        }
        return nil
    }

    /// The text of the page's line `line`, counting from 0, without its line break: each of the
    /// document's blocks is a line of the text.
    static func range(ofLine line: Int, in text: NSString) -> NSRange? {
        var count = 0
        var found: NSRange?
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, stop in
            if count == line {
                found = range
                stop.pointee = true
            }
            count += 1
        }
        return found
    }

    #if canImport(UIKit)
    /// Readies the page to be moved to with the keyboard up: it shows up scrolled to its caret,
    /// which goes to the end the first time, as it will when the page is focused.
    func arrive() {
        placeCaretIfNew()
        textView.arrive()
    }
    #endif

    private func placeCaretIfNew() {
        guard caretGoesToEnd else { return }
        caretGoesToEnd = false
        textView.selectedRange = NSRange(location: max(0, storage.length - 1), length: 0)
    }

    // MARK: The text view's own edits

    /// Asked before the text view changes the text itself: typing, backspace, Return, Tab, an
    /// input method, cut. Returns false where the editor makes the change instead.
    func shouldChange(_ range: NSRange, to text: String) -> Bool {
        guard !isApplyingEdit else { return true }
        // UIKit's undo and redo put back text with the attributes it had; stamping it with the
        // line's style, as for typing, turned a restored bold word plain.
        if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing { return true }
        let edited = NSRange(location: range.location, length: (text as NSString).length)
        // Never touch text while an input method is still composing it (marked text).
        guard !textView.isComposing else {
            recordPendingEdit(replacing: range, composing: true)
            return true
        }
        // The final newline stays, so it can't be deleted or replaced.
        var range = range
        let reachesFinalNewline = range.length > 0 && NSMaxRange(range) == storage.length && !text.hasSuffix("\n")
        if reachesFinalNewline {
            range.length -= 1
            if range.length == 0, text.isEmpty { return false }
        }
        if text == "\n", range.length > 0 {
            returnOverSelection(range)
            return false
        }
        if range.length > 0, string.substring(with: range).contains("\n") {
            if text.isEmpty {
                // The keyboard asks about a backspace before it sends one, and a "no" means it
                // doesn't. At the start of a line it asks about the line break before the caret,
                // and the backspace rules decide what happens there.
                let caret = textView.selectedRange
                if range.length == 1, caret.length == 0, caret.location == NSMaxRange(range), handleBackspace() {
                    return false
                }
                joinLines(deleting: range)
                return false
            }
            // Typing over lines is left to UIKit: an input method asks this too before it starts
            // composing, and a "no" would leave its first letter as plain text. UIKit's undo puts
            // back only what it replaced, so a line that joins in whole gets its own back here.
            if isLineStart(NSMaxRange(range)) {
                registerUndoOfJoin(lineAt: NSMaxRange(range))
            }
        }
        if reachesFinalNewline {
            replace(range, with: NSAttributedString(string: text, attributes: lineBreakAttributes(for: block(of: lineRange(at: range.location)))),
                    selection: NSRange(location: range.location + edited.length, length: 0))
            return false
        }
        if range.length == 0 {
            if text == "\n", handleReturn(at: range.location) { return false }
            if text == "\t", changeIndent(by: 1) { return false }
            if text.count == 1, handleTyped(text, at: range.location) { return false }
        }
        recordPendingEdit(replacing: range, composing: false)
        return true
    }

    /// The text view changed the text, after `shouldChange` let it.
    func textChanged() {
        guard !isApplyingEdit, !textView.isComposing else { return }
        var changed = textView.selectedRange
        // UIKit said it made this change, so it's put right here rather than as a change it made
        // on its own.
        let unannounced = unannouncedEdit.map { clampToPage($0.range) }
        unannouncedEdit = nil
        // A change with no edit on record (dictation, an undo) may have changed any line.
        var withinLine = false
        var joinedLine: Int?
        if let unannounced, pendingEdit == nil {
            changed = NSUnionRange(changed, unannounced)
        }
        if let edit = pendingEdit {
            pendingEdit = nil
            apply(edit)
            let inserted = edit.insertedRange(inPageOfLength: storage.length)
            changed = NSUnionRange(changed, inserted)
            withinLine = !edit.joinsLines && !string.substring(with: inserted).contains("\n")
            if edit.joinsLines { joinedLine = edit.location }
        }
        contentDidChange(in: changed, withinLine: withinLine)
        if let joinedLine { registerRedoOfJoin(lineAt: joinedLine) }
    }

    func selectionChanged() {
        guard !isApplyingEdit, !textView.isComposing else { return }
        // A tap put the caret somewhere.
        caretGoesToEnd = false
        let clamped = stepOverDivider(clamp(textView.selectedRange))
        defer { lastCaretLocation = clamped.location }
        if clamped != textView.selectedRange {
            // Setting it comes back here; it's where it should be then, but never go round twice.
            guard !isMovingSelection else { return }
            isMovingSelection = true
            textView.selectedRange = clamped
            isMovingSelection = false
            return
        }
        if let override = typingOverride, override.location != clamped.location || clamped.length > 0 {
            typingOverride = nil
        }
        updateTypingAttributes()
    }

    #if canImport(UIKit)
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        shouldChange(range, to: text)
    }

    func textViewDidChange(_ textView: UITextView) {
        textChanged()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        selectionChanged()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        let bar = FormatBar.shared
        bar.editor = self
        bar.tintColor = theme.accent
        bar.refresh()
        onBeginEditing?()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        textView.hideFound()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        textView.dragDidEnd()
    }
    #else
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // No text means a change of attributes alone, from AppKit's font panel and the like. A
        // page's look comes from its lines and styles, so those go through the editor too.
        guard let replacementString else { return false }
        return shouldChange(affectedCharRange, to: replacementString)
    }

    func textDidChange(_ notification: Notification) {
        textChanged()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        selectionChanged()
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                  toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
        allowedSelection(newSelectedCharRange)
    }

    /// Where the selection may be: never past the final newline, and a caret never on a divider.
    /// The text view asks every time the selection is set, a drag that's still selecting
    /// included, so the selection is never anywhere else, not even for a moment.
    func allowedSelection(_ range: NSRange) -> NSRange {
        guard !isApplyingEdit, !textView.isComposing, storage.length > 0 else { return range }
        return stepOverDivider(clamp(range))
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        pageUndoManager
    }

    /// Code is no prose, so spelling isn't checked in it.
    func textView(_ view: NSTextView, didCheckTextIn range: NSRange, types checkingTypes: NSTextCheckingTypes,
                  options: [NSSpellChecker.OptionKey: Any], results: [NSTextCheckingResult], orthography: NSOrthography,
                  wordCount: Int) -> [NSTextCheckingResult] {
        results.filter { result in
            let location = result.range.location
            guard location < storage.length else { return true }
            return block(of: lineRange(at: location)).kind != .code && !inlineStyle(at: location).contains(.code)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertBacktab(_:)):
            perform(.outdent)
            return true
        case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            // A page is made of lines, with no breaks inside one: these are Return too.
            textView.insertNewline(nil)
            return true
        default:
            return false
        }
    }
    #endif

    // MARK: Typed text

    /// Where a user edit lands and which line and inline style it belongs to.
    private struct PendingEdit {
        let location: Int
        /// The page's length before the edit, and how much of it the edit replaced.
        let lengthBefore: Int
        let replacedLength: Int
        let block: BlockAttributes
        let inline: InlineStyle
        /// The link the new text is part of: typed inside one, or over some of its text.
        let link: String?
        /// The edit deletes at least one line break, joining lines.
        let joinsLines: Bool

        /// The text the edit put in, worked out from how much the page grew. An input method
        /// rewrites its marked text many times before settling, often on something shorter than
        /// what was spelled, so adding up those steps overshot into the next line and restyled it.
        func insertedRange(inPageOfLength length: Int) -> NSRange {
            let start = min(location, length)
            let inserted = max(0, length - lengthBefore + replacedLength)
            return NSRange(location: start, length: min(inserted, length - start))
        }
    }

    /// UIKit inserts typed text with its own typing attributes, which it resets whenever the caret
    /// moves, and which can come from the line above. So every edit is remembered here and the
    /// new text is stamped with its line's attributes afterwards (`apply`).
    private func recordPendingEdit(replacing range: NSRange, composing: Bool) {
        // While composing, each update replaces the marked text; keep the first line and style.
        if composing, let edit = pendingEdit {
            textView.typingAttributes = typingAttributes(atLineOf: edit.location, inline: edit.inline, link: edit.link)
            return
        }
        let block = block(of: lineRange(at: range.location))
        // Typing over text carries on in the style of that text.
        let inline = range.length > 0 && block.kind != .code ? inlineStyle(at: range.location) : typingStyle(at: range.location)
        let link = linkContinued(by: range)
        let joinsLines = range.length > 0 && string.substring(with: range).contains("\n")
        pendingEdit = PendingEdit(location: range.location, lengthBefore: storage.length, replacedLength: range.length,
                                  block: block, inline: inline, link: link, joinsLines: joinsLines)
        // The text goes in with the attributes it's due, not only stamped with them afterwards
        // (`apply`): UIKit's undo and redo bring it back as it went in. Text being composed in
        // an input method went in with none when UIKit had reset the typing attributes, and
        // undoing it passed through a state where it started the line, so the line lost its kind.
        textView.typingAttributes = typingAttributes(atLineOf: range.location, inline: inline, link: link)
    }

    /// Return with text selected: the selection goes, then Return does what it does at the
    /// caret, so a to-do carries on unchecked and the rest of a heading becomes a paragraph.
    private func returnOverSelection(_ selection: NSRange) {
        let range = NSRange(location: selection.location, length: min(selection.length, storage.length - 1 - selection.location))
        if string.substring(with: range).contains("\n") {
            joinLines(deleting: range)
        } else {
            replace(range, with: NSAttributedString(), selection: NSRange(location: range.location, length: 0))
        }
        guard !handleReturn(at: range.location) else { return }
        let lineBreak = NSAttributedString(string: "\n", attributes: lineBreakAttributes(for: block(of: lineRange(at: range.location))))
        replace(NSRange(location: range.location, length: 0), with: lineBreak, selection: NSRange(location: range.location + 1, length: 0))
    }

    /// Deleting text that spans lines joins what's left of them into one line, which keeps the
    /// kind of the line the deletion started on, like in Notion. Deleting whole lines, from the
    /// start of one to the start of another, joins nothing: the line after them stays as it is.
    /// The edit is made here rather than by UIKit so that undo can bring back the kinds of the
    /// joined lines, not just their characters.
    private func joinLines(deleting range: NSRange) {
        let startLine = lineRange(at: range.location)
        let start = block(of: startLine)
        let wholeLines = range.length > 1 && range.location == startLine.location && isLineStart(NSMaxRange(range))
        replaceAcrossLines(range, with: NSAttributedString(), joinedLineKeeps: wholeLines ? nil : start,
                           selection: NSRange(location: range.location, length: 0))
    }

    /// Text typed over lines leaves one line, which takes the first one's kind, the rest of the
    /// last line included. UIKit's redo only puts back what it typed, so a redone join kept the
    /// rest of that line as it was before: an empty line typed after it came back numbered.
    ///
    /// So the join gets a step of its own, after UIKit's. Undone, it does nothing (it goes first,
    /// before UIKit takes its text back) but leave a redo step. That one runs after UIKit's redo
    /// and gives the joined line the attributes it had.
    private func registerRedoOfJoin(lineAt location: Int) {
        let line = lineRange(at: location)
        let joined = storage.attributedSubstring(from: line)
        textView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                controller.textView.undoManager?.registerUndo(withTarget: controller) { controller in
                    MainActor.assumeIsolated {
                        let range = NSRange(location: line.location, length: joined.length)
                        guard controller.textIsStill(joined.string, at: range) else { return }
                        controller.replace(range, with: joined, selection: controller.textView.selectedRange)
                    }
                }
            }
        }
    }

    /// For typing over text that ends at the start of a line: that line joins the first one and
    /// takes its kind. Undo puts UIKit's text back first, then this puts back the line's own
    /// attributes, as long as its text is back where it was.
    private func registerUndoOfJoin(lineAt location: Int) {
        let line = lineRange(at: location)
        let original = storage.attributedSubstring(from: line)
        textView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                let range = NSRange(location: line.location, length: original.length)
                guard controller.textIsStill(original.string, at: range) else { return }
                controller.replace(range, with: original, selection: controller.textView.selectedRange)
            }
        }
    }

    /// Replaces a range that spans lines by rewriting every line it touches, and the line after
    /// it: a join gives that line's text the kind of the line it joins, and undo can only put
    /// back what it replaced. `block` goes on the line where the replacement starts.
    private func replaceAcrossLines(_ range: NSRange, with inserted: NSAttributedString, joinedLineKeeps block: BlockAttributes?, selection: NSRange) {
        let lines = NSUnionRange(string.paragraphRange(for: range), lineRange(at: NSMaxRange(range)))
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: lines))
        let local = NSRange(location: range.location - lines.location, length: range.length)
        replacement.replaceCharacters(in: local, with: inserted)
        let joined = (replacement.string as NSString).paragraphRange(for: NSRange(location: local.location, length: 0))
        if replacement.length == 1, lines.length == storage.length {
            // Clearing the whole page leaves a plain, empty paragraph.
            replacement.setAttributes(lineBreakAttributes(for: BlockAttributes()), range: NSRange(location: 0, length: 1))
        } else if let block {
            replacement.addAttributes(block.dictionary, range: joined)
        }
        replace(lines, with: replacement, selection: selection)
    }

    /// Whether the line or lines `selection` is on have text before or after it.
    private func hasText(besides selection: NSRange) -> Bool {
        let first = lineRange(at: selection.location)
        let last = lineRange(at: NSMaxRange(selection))
        return selection.location > first.location || NSMaxRange(selection) < contentRange(of: last).upperBound
    }

    private func isLineStart(_ location: Int) -> Bool {
        location == 0 || string.character(at: location - 1) == 0x0A
    }

    private func apply(_ edit: PendingEdit) {
        isApplyingEdit = true
        storage.beginEditing()
        let inserted = edit.insertedRange(inPageOfLength: storage.length)
        if inserted.length > 0 {
            var attributes = edit.block.dictionary
            attributes[.biteInline] = edit.inline.rawValue
            storage.addAttributes(attributes, range: inserted)
            if let link = edit.link {
                storage.addAttribute(.biteLink, value: link, range: inserted)
            } else {
                storage.removeAttribute(.biteLink, range: inserted)
            }
        }
        if edit.joinsLines {
            // Only an input method still gets here with a join (see `joinLines`). Joined lines
            // keep the kind of the line the edit started on; clearing the whole page leaves a
            // plain, empty paragraph.
            let block = storage.length <= 1 ? BlockAttributes() : edit.block
            storage.addAttributes(block.dictionary, range: lineRange(at: edit.location))
        }
        storage.endEditing()
        isApplyingEdit = false
    }

    // MARK: Shortcuts

    /// The characters that can set a shortcut off.
    private static let shortcutTriggers = InputRules.inlineMarkers.union([" ", "\u{3000}", "-", "`", "\u{00B7}", ")"])

    /// Returns true when `character` completed a shortcut and was consumed.
    private func handleTyped(_ character: String, at location: Int) -> Bool {
        guard Self.shortcutTriggers.contains(character) else { return false }
        let line = lineRange(at: location)
        let block = block(of: line)
        let prefixRange = NSRange(location: line.location, length: location - line.location)
        let prefix = string.substring(with: prefixRange)
        let content = contentRange(of: line)
        let restOfLineIsEmpty = location == content.upperBound

        if block.kind == .code {
            if restOfLineIsEmpty, InputRules.closesCodeBlock(prefix: prefix, typed: character) {
                convert(line, removingPrefix: prefix, to: InputRules.BlockChange(.paragraph), from: block, typed: character)
                return true
            }
            return false
        }
        guard block.kind != .divider else { return false }
        // Inline code is code: what's typed in it goes in as typed. Two stars in it used to
        // turn the text between them bold and take the stars out of the code.
        guard !typingStyle(at: location).contains(.code) else { return false }
        // Code earlier on the line is text too. A marker in it doesn't start a block, and
        // stands in for no marker of an inline shortcut.
        let code = codeRanges(in: prefixRange)

        switch character {
        case " ", "\u{3000}":
            // A full-width space (U+3000) comes from Chinese keyboards set to full width.
            if code.isEmpty, let change = InputRules.blockShortcut(forPrefix: prefix) {
                convert(line, removingPrefix: prefix, to: change, from: block, typed: character)
                return true
            }
        case "-", "`", "\u{00B7}":
            // Three backticks turn the text after them into code, as in Notion. A divider holds
            // no text, so `---` only works on an empty line.
            if code.isEmpty, let kind = InputRules.lineShortcut(forPrefix: prefix, typed: character), kind == .code || restOfLineIsEmpty {
                makeLine(line, removingPrefix: prefix, kind: kind, typed: character)
                return true
            }
        default:
            break
        }
        // Code stands in as characters that are neither spaces, letters nor markers, the way
        // its backticks sit in Markdown. Same length, so the match's offsets still hold.
        let text = NSMutableString(string: prefix)
        for range in code {
            text.replaceCharacters(in: range, with: String(repeating: "#", count: range.length))
        }
        if character == ")" {
            guard let match = InputRules.linkShortcut(prefix: text as String) else { return false }
            applyLink(match, lineStart: line.location, caret: location)
            return true
        }
        guard InputRules.inlineMarkers.contains(character) else { return false }
        let following = location < content.upperBound ? string.substring(with: string.rangeOfComposedCharacterSequence(at: location)).first : nil
        guard let match = InputRules.inlineShortcut(prefix: text as String, typed: character, following: following) else { return false }
        applyInline(match, lineStart: line.location, caret: location, typed: character)
        return true
    }

    /// Where inline code is in `range`, relative to its start.
    private func codeRanges(in range: NSRange) -> [NSRange] {
        guard range.length > 0 else { return [] }
        return inlineRuns(in: storage, range: range).compactMap { run, style in
            style.contains(.code) ? NSRange(location: run.location - range.location, length: run.length) : nil
        }
    }

    private func convert(_ line: NSRange, removingPrefix prefix: String, to change: InputRules.BlockChange, from current: BlockAttributes, typed: String) {
        let keepIndent = current.kind.isList && change.kind.isList
        let block = BlockAttributes(kind: change.kind, indent: keepIndent ? current.indent : 0, isChecked: change.isChecked,
                                    number: change.number, numberStyle: change.numberStyle)
        let prefixLength = (prefix as NSString).length
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: line))
        replacement.deleteCharacters(in: NSRange(location: 0, length: prefixLength))
        replacement.addAttributes(block.dictionary, range: NSRange(location: 0, length: replacement.length))
        let undo = undoForShortcut(replacing: line, typed: typed, at: line.location + prefixLength)
        replace(line, with: replacement, selection: NSRange(location: line.location, length: 0), undo: undo)
    }

    /// `---` and three backticks.
    private func makeLine(_ line: NSRange, removingPrefix prefix: String, kind: BlockKind, typed: String) {
        let prefixLength = (prefix as NSString).length
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: line))
        replacement.deleteCharacters(in: NSRange(location: 0, length: prefixLength))
        replacement.addAttributes(BlockAttributes(kind: kind).dictionary, range: NSRange(location: 0, length: replacement.length))
        var caret = line.location
        if kind == .divider {
            // A divider holds no text, so carry on in a new paragraph below it.
            replacement.append(NSAttributedString(string: "\n", attributes: lineBreakAttributes(for: BlockAttributes())))
            caret += 1
        }
        let undo = undoForShortcut(replacing: line, typed: typed, at: line.location + prefixLength)
        replace(line, with: replacement, selection: NSRange(location: caret, length: 0), undo: undo)
    }

    private func applyInline(_ match: InputRules.InlineMatch, lineStart: Int, caret: Int, typed: String) {
        let start = lineStart + match.range.lowerBound
        let contentRange = NSRange(location: lineStart + match.content.lowerBound, length: match.content.count)
        let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: contentRange))
        for (range, style) in inlineRuns(in: content) {
            content.addAttribute(.biteInline, value: style.union(match.style).rawValue, range: range)
        }
        let styleBefore = start > lineStart ? inlineStyle(at: start - 1) : []
        let end = start + content.length
        let replaced = NSRange(location: start, length: caret - start)
        let undo = undoForShortcut(replacing: replaced, typed: typed, at: caret)
        replace(replaced, with: content, selection: NSRange(location: end, length: 0), undo: undo)
        typingOverride = (styleBefore.subtracting(match.style), end)
        updateTypingAttributes()
    }

    /// `[text](address)` typed: the text, with its styles, becomes a link, and typing goes on after
    /// it as plain text.
    private func applyLink(_ match: InputRules.LinkMatch, lineStart: Int, caret: Int) {
        let start = lineStart + match.range.lowerBound
        let text = NSRange(location: lineStart + match.text.lowerBound, length: match.text.count)
        let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: text))
        content.addAttribute(.biteLink, value: LinkDetector.destination(forTyped: match.destination),
                             range: NSRange(location: 0, length: content.length))
        let replaced = NSRange(location: start, length: caret - start)
        let undo = undoForShortcut(replacing: replaced, typed: ")", at: caret)
        replace(replaced, with: content, selection: NSRange(location: start + content.length, length: 0), undo: undo)
        updateTypingAttributes()
    }

    /// What undo brings back after a shortcut: the text as it was plus the character that set the
    /// shortcut off, so undo leaves exactly what was typed (`- `, `**bold**`), caret after it.
    ///
    /// That character never went into the text, so it also gets an undo step of its own, the one
    /// after: without it, undoing on took away everything typed before it and left it behind.
    private func undoForShortcut(replacing range: NSRange, typed: String, at location: Int) -> (text: NSAttributedString, selection: NSRange) {
        if let undoManager = textView.undoManager {
            let typedRange = NSRange(location: location, length: (typed as NSString).length)
            undoManager.registerUndo(withTarget: self) { controller in
                MainActor.assumeIsolated {
                    guard controller.textIsStill(typed, at: typedRange) else { return }
                    controller.replace(typedRange, with: NSAttributedString(), selection: NSRange(location: location, length: 0))
                }
            }
            // The shortcut's own undo, registered next, goes in a group of its own.
            if undoManager.groupingLevel > 0 {
                undoManager.endUndoGrouping()
                undoManager.beginUndoGrouping()
            }
        }
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attributes = lineBreakAttributes(for: block(of: lineRange(at: location)))
        text.insert(NSAttributedString(string: typed, attributes: attributes), at: location - range.location)
        return (text, NSRange(location: location + (typed as NSString).length, length: 0))
    }

    // MARK: Return, backspace, indent

    private func handleReturn(at location: Int) -> Bool {
        let line = lineRange(at: location)
        let block = block(of: line)
        let content = contentRange(of: line)
        let nextKind = NSMaxRange(line) < storage.length ? self.block(of: lineRange(at: NSMaxRange(line))).kind : nil
        let action = InputRules.returnAction(
            kind: block.kind,
            indent: block.indent,
            lineIsEmpty: content.isEmpty,
            caretAtStart: location == line.location,
            nextKind: nextKind
        )
        let tailRange = NSRange(location: location, length: NSMaxRange(line) - location)
        switch action {
        case .insertNewline:
            return false
        case .exitBlock:
            setBlocks(of: [line]) { $0 = BlockAttributes() }
        case .outdent:
            setBlocks(of: [line]) { $0.indent -= 1 }
        case .continueBlock, .splitToParagraph:
            // The text after the caret moves to a new line: the same kind for lists and code
            // (a new to-do starts unchecked), a plain paragraph for everything else.
            // A new item carries on its list's style.
            var next = block
            next.isChecked = false
            next.number = nil
            next.numberStyle = (storage.attribute(.biteShownStyle, at: line.location, effectiveRange: nil) as? String)
                .flatMap(NumberStyle.init(rawValue:))
            if action == .splitToParagraph { next = BlockAttributes() }
            let tail = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: tailRange))
            tail.addAttributes(next.dictionary, range: NSRange(location: 0, length: tail.length))
            let replacement = NSMutableAttributedString(string: "\n", attributes: lineBreakAttributes(for: block))
            replacement.append(tail)
            replace(tailRange, with: replacement, selection: NSRange(location: location + 1, length: 0))
        case .itemAbove, .paragraphAbove:
            // Open a line above and keep the caret with the text, which stays as it is. A new
            // first item takes over the number the list starts at.
            var above = BlockAttributes()
            if action == .itemAbove {
                above = block
                above.isChecked = false
            }
            let lineBreak = NSAttributedString(string: "\n", attributes: lineBreakAttributes(for: above))
            replace(NSRange(location: line.location, length: 0), with: lineBreak, selection: NSRange(location: location + 1, length: 0))
        }
        return true
    }

    /// Called by the text view before a backspace. Returns true when it was handled here.
    func handleBackspace() -> Bool {
        let selection = textView.selectedRange
        guard selection.length == 0, storage.length > 0 else { return false }
        let line = lineRange(at: selection.location)
        guard selection.location == line.location else { return false }
        let block = block(of: line)
        let previousKind = line.location > 0 ? self.block(of: lineRange(at: line.location - 1)).kind : nil
        switch InputRules.backspaceAtLineStart(kind: block.kind, indent: block.indent, previousKind: previousKind) {
        case .deleteCharacter:
            return false
        case .outdent:
            setBlocks(of: [line]) { $0.indent -= 1 }
        case .convertToParagraph:
            setBlocks(of: [line]) { $0 = BlockAttributes() }
        case .deleteLineAbove:
            let above = lineRange(at: line.location - 1)
            replace(above, with: NSAttributedString(), selection: NSRange(location: above.location, length: 0))
        }
        return true
    }

    /// Tab, Shift-Tab and the indent buttons. A line can go at most one level deeper than the
    /// list line above it, and the items nested under it move with it, as in Notion. Returns
    /// false when no list line was selected.
    @discardableResult
    private func changeIndent(by delta: Int) -> Bool {
        let selected = selectedLines()
        guard let last = selected.last, selected.contains(where: { block(of: $0).kind.isList }) else { return false }
        var previousIndent: Int?
        if let first = selected.first, first.location > 0 {
            let above = block(of: lineRange(at: first.location - 1))
            previousIndent = above.kind.isList ? above.indent : nil
        }
        var lines = selected
        var indents: [Int] = []
        // Each selected item's indent before, and how far it moved.
        var parents: [(indent: Int, change: Int)] = []
        for line in selected {
            let block = block(of: line)
            guard block.kind.isList else {
                indents.append(0)
                previousIndent = nil
                parents.removeAll()
                continue
            }
            // No deeper than one level below the line above, or than the deepest level that
            // indents (though a deeper line from Markdown stays where it is).
            let deepest = max(block.indent, EditorTheme.deepestIndent)
            let indent = min(max(0, block.indent + delta), (previousIndent ?? -1) + 1, deepest)
            indents.append(indent)
            parents.append((block.indent, indent - block.indent))
            previousIndent = indent
        }
        // The items after the selection that hang under one of its items go the same way.
        var position = NSMaxRange(last)
        while position < storage.length {
            let line = lineRange(at: position)
            let block = block(of: line)
            guard block.kind.isList, let parent = parents.last(where: { $0.indent < block.indent }) else { break }
            lines.append(line)
            indents.append(max(0, block.indent + parent.change))
            position = NSMaxRange(line)
        }
        var index = 0
        setBlocks(of: lines) { block in
            // An item moved to another level joins the list there or starts one, which goes by
            // its own style or its level's, not the style of the list it came from.
            if block.indent != indents[index] { block.numberStyle = nil }
            block.indent = indents[index]
            index += 1
        }
        return true
    }

    /// Text an input method is still composing is committed before the editor changes the text
    /// itself, as a tap elsewhere in the text commits it. Rewritten under the input method, it
    /// lost its marked text: the letters spelled so far stayed in the text without the input
    /// method being told it was done with them.
    private func finishComposing() {
        guard textView.isComposing else { return }
        textView.unmarkText()
    }

    // MARK: Format bar and menu actions

    /// Empties the page as one edit, which undo brings back: Clear Text asks for no
    /// confirmation, so a slip of the finger is one undo away.
    func clear() {
        finishComposing()
        typingOverride = nil
        replace(NSRange(location: 0, length: storage.length), with: styledText(for: BiteDocument()),
                selection: NSRange(location: 0, length: 0))
        reportPendingChange()
    }

    func perform(_ action: FormatAction) {
        finishComposing()
        switch action {
        case .todo: toggleKind(.todo)
        case .bullet: toggleKind(.bullet)
        case .ordered: toggleKind(.ordered)
        case .heading: cycleHeading()
        case .quote: toggleKind(.quote)
        case .code: toggleKind(.code)
        case .bold: toggleInline(.bold)
        case .italic: toggleInline(.italic)
        case .strikethrough: toggleInline(.strikethrough)
        case .link: editLink()
        case .outdent: changeIndent(by: -1)
        case .indent: changeIndent(by: 1)
        case .dismiss:
            #if canImport(UIKit)
            textView.resignFirstResponder()
            #else
            textView.window?.makeFirstResponder(nil)
            #endif
        }
    }

    /// The styles the format bar shows as on: those that typing at the caret gets, or that all the
    /// selected text has. Tapping the button of one that's on undoes it.
    var activeStyles: InlineStyle {
        guard storage.length > 0 else { return [] }
        let selection = clamp(textView.selectedRange)
        guard selection.length > 0 else { return typingStyle(at: selection.location) }
        let styles = inlineStyles(in: selection)
        guard let first = styles.first else { return [] }
        return styles.dropFirst().reduce(first) { $0.intersection($1) }
    }

    /// Dividers in the selection stay as they are: they hold no text to turn into anything.
    private func toggleKind(_ kind: BlockKind) {
        let lines = selectedLines().filter { block(of: $0).kind != .divider }
        guard !lines.isEmpty else { return }
        let allMatch = lines.allSatisfy { block(of: $0).kind == kind }
        setBlocks(of: lines) { block in
            let wasList = block.kind.isList
            block.kind = allMatch ? .paragraph : kind
            if !(wasList && block.kind.isList) { block.indent = 0 }
            if block.kind != .todo { block.isChecked = false }
        }
    }

    private func cycleHeading() {
        let lines = selectedLines().filter { block(of: $0).kind != .divider }
        guard let first = lines.first else { return }
        let next: BlockKind = switch block(of: first).kind {
        case .heading1: .heading2
        case .heading2: .heading3
        // Levels 4 to 6 look like 3, so they come next to it.
        case .heading3, .heading4, .heading5, .heading6: .paragraph
        default: .heading1
        }
        setBlocks(of: lines) { $0 = BlockAttributes(kind: next) }
    }

    func toggleInline(_ style: InlineStyle) {
        let selection = clamp(textView.selectedRange)
        guard selection.length > 0 else {
            guard block(of: lineRange(at: selection.location)).kind != .code else { return }
            typingOverride = (typingStyle(at: selection.location).symmetricDifference(style), selection.location)
            updateTypingAttributes()
            return
        }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
        let allHaveStyle = inlineStyles(in: selection).allSatisfy { $0.contains(style) }
        for (range, current) in inlineRuns(in: replacement) {
            let updated = allHaveStyle ? current.subtracting(style) : current.union(style)
            replacement.addAttribute(.biteInline, value: updated.rawValue, range: range)
        }
        replace(selection, with: replacement, selection: selection)
    }

    // MARK: Links

    /// A link on the page: where its text is, and where it goes.
    struct PageLink: Equatable, Identifiable {
        var range: NSRange
        var text: String
        /// As the Markdown has it, or where an address written out in the text goes.
        var destination: String
        /// An address written out in the text, which shows as a link but is plain text.
        var isWrittenOut: Bool
        /// Not on the page yet: the selected text to link, or the caret, where a link goes.
        var isNew = false

        var id: String { "\(range.location) \(range.length) \(destination)" }

        /// Where the link goes, to change: an address written out, or text that says its address,
        /// as it's written. `apple.com` made into a link goes to `https://apple.com`, and comes up
        /// as `apple.com` again, changing nothing if left so.
        var address: String { saysItsAddress ? text : destination }

        /// Whether the text says where the link goes, as an address written out does, or
        /// `example.com` going to `https://example.com`, or to `example.com` in a page from
        /// elsewhere: the format bar leaves its text row empty, the address standing in, in grey.
        var saysItsAddress: Bool {
            !isNew && (isWrittenOut || LinkDetector.destination(forTyped: text) == LinkDetector.destination(forTyped: destination))
        }

        /// Where `destination` goes. One from elsewhere may lack its scheme, which Bite's own
        /// links have (see `LinkDetector.destination(forTyped:)`).
        static func url(for destination: String) -> URL? {
            let full = LinkDetector.destination(forTyped: destination)
            return full.isEmpty ? nil : URL(string: full)
        }
    }

    /// The link whose text is at `location`, if there is one.
    func link(at location: Int) -> PageLink? {
        guard location >= 0, location < storage.length - 1 else { return nil }
        let content = contentRange(of: lineRange(at: location))
        let line = NSRange(location: content.lowerBound, length: content.count)
        guard NSLocationInRange(location, line) else { return nil }
        var range = NSRange()
        if let destination = storage.attribute(.biteLink, at: location, longestEffectiveRange: &range, in: line) as? String {
            // An address kept from being a link is text.
            guard !destination.isEmpty else { return nil }
            return PageLink(range: range, text: string.substring(with: range), destination: destination, isWrittenOut: false)
        }
        if let address = storage.attribute(.biteWrittenLink, at: location, longestEffectiveRange: &range, in: line) as? String {
            return PageLink(range: range, text: address, destination: LinkDetector.destination(of: address), isWrittenOut: true)
        }
        return nil
    }

    /// Whether the selection is a link's text, all or part of it, an address written out too:
    /// the format bar's link button shows as on, as bold does over bold text, and takes the link
    /// off what's selected. Not for a caret, even in a link, nor for a selection a link is only
    /// part of, which the button makes one link of.
    var isLinkSelected: Bool {
        let selection = clamp(textView.selectedRange)
        return selection.length > 0 && linkAround(selection) != nil
    }

    /// A tap on a link's text, while the page isn't being edited: goes where the link goes.
    func openLink(at location: Int) {
        guard let link = link(at: location), let url = PageLink.url(for: link.destination) else { return }
        openURL(url)
    }

    /// A tap on a link's text while the page is being edited: the link is changed in the format
    /// bar, its text and where it goes, a link one letter long as well as any. The caret stays where
    /// it was; held down, a link's text takes the caret, as any text does.
    func editLink(at location: Int) {
        // The link being changed, as it's typed, stays as it is.
        guard !isInLinkPreview(location), let link = link(at: location) else { return }
        onEditLink?(link)
    }

    /// The format bar's link button: the link at the caret or around the selection, or the
    /// selected text to make one of, or the caret, where a new one goes.
    private func editLink() {
        let selection = clamp(textView.selectedRange)
        if let plain = plainAddress(around: selection) {
            setLinkAttribute(nil, on: plain)
            return
        }
        guard let link = linkToEdit() else { return }
        if selection.length > 0, !link.isNew {
            if link.isWrittenOut {
                setLinkAttribute("", on: link.range)
            } else {
                unlink(selection)
            }
            return
        }
        if link.isNew, takeIntoLink(selection) { return }
        onEditLink?(link)
    }

    /// Takes the link off the selected part of a link's text, as bold comes off just what's
    /// selected: the rest of the link, before and after, stays one. All of it selected, the link
    /// goes, its text staying.
    private func unlink(_ selection: NSRange) {
        let unlinked = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
        unlinked.removeAttribute(.biteLink, range: NSRange(location: 0, length: unlinked.length))
        keepAddressesPlain(in: unlinked, at: selection)
        replace(selection, with: unlinked, selection: selection)
    }

    /// Puts `link` on the text at `range`, or takes it off, as one edit, the text and the
    /// selection staying as they are. An empty link keeps an address written out from being one.
    private func setLinkAttribute(_ link: String?, on range: NSRange) {
        let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let all = NSRange(location: 0, length: text.length)
        if let link {
            text.addAttribute(.biteLink, value: link, range: all)
        } else {
            text.removeAttribute(.biteLink, range: all)
        }
        replace(range, with: text, selection: clamp(textView.selectedRange))
    }

    /// The address kept from being a link, with an empty link, that the selection is within or
    /// the caret is strictly inside: the link button makes it one again.
    private func plainAddress(around selection: NSRange) -> NSRange? {
        guard selection.location < storage.length - 1 else { return nil }
        let content = contentRange(of: lineRange(at: selection.location))
        let line = NSRange(location: content.lowerBound, length: content.count)
        var range = NSRange()
        guard NSLocationInRange(selection.location, line),
              storage.attribute(.biteLink, at: selection.location, longestEffectiveRange: &range, in: line) as? String == "" else { return nil }
        guard selection.length > 0 else { return range.location < selection.location ? range : nil }
        return NSMaxRange(selection) <= NSMaxRange(range) ? range : nil
    }

    /// Addresses written out in `text`, put in for `range`, kept from showing as links: they're
    /// in text a link is coming off, and by their own text they'd be links again.
    private func keepAddressesPlain(in text: NSMutableAttributedString, at range: NSRange) {
        let content = contentRange(of: lineRange(at: range.location))
        let line = NSMutableString(string: string.substring(with: NSRange(location: content.lowerBound, length: content.count)))
        let local = NSRange(location: range.location - content.lowerBound, length: range.length)
        line.replaceCharacters(in: local, with: text.string)
        for address in LinkDetector.addresses(in: line as String)
        where address.lowerBound >= local.location && address.upperBound <= local.location + text.length {
            text.addAttribute(.biteLink, value: "", range: NSRange(location: address.lowerBound - local.location, length: address.count))
        }
    }

    /// Selected text that takes in a link, or part of one, and words beside it, becomes that link
    /// at once, all of it, with nothing to type: the words join the link, and its text beyond the
    /// selection stays in it. Typing on at a link's end leaves the link as it was, so it takes in
    /// words this way. The selection stays as it was made. Taking in more than one link, it goes
    /// where the first went. Says whether there was a link to take in.
    private func takeIntoLink(_ selection: NSRange) -> Bool {
        guard selection.length > 0 else { return false }
        var whole = selection
        var destination: String?
        var location = selection.location
        while location < NSMaxRange(selection) {
            guard let link = link(at: location) else {
                location += 1
                continue
            }
            destination = destination ?? link.destination
            whole = NSUnionRange(whole, link.range)
            location = NSMaxRange(link.range)
        }
        guard let destination else { return false }
        let linked = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: whole))
        linked.addAttribute(.biteLink, value: destination, range: NSRange(location: 0, length: linked.length))
        replace(whole, with: linked, selection: selection)
        return true
    }

    /// Whether the link button has a link to change or make where the caret or selection is. It
    /// dims where it hasn't: pressed there, it did nothing, and said nothing.
    var canEditLink: Bool {
        linkToEdit() != nil
    }

    /// The link the link button is for: the one at the caret or around the selection, or a new one
    /// of the selected text or at the caret. None in code, or across lines.
    private func linkToEdit() -> PageLink? {
        let selection = clamp(textView.selectedRange)
        if let link = linkAround(selection) { return link }
        let line = lineRange(at: selection.location)
        // Code holds no links, and a link holds no line break.
        let inCode = selection.length > 0 ? inlineStyles(in: selection).contains { $0.contains(.code) } : typingStyle(at: selection.location).contains(.code)
        guard ![.code, .divider].contains(block(of: line).kind), !inCode, !string.substring(with: selection).contains("\n") else { return nil }
        return PageLink(range: selection, text: string.substring(with: selection), destination: "", isWrittenOut: false, isNew: true)
    }

    /// The page's links, in order.
    func links() -> [PageLink] {
        let all = NSRange(location: 0, length: storage.length)
        var starts: [Int] = []
        for key in [NSAttributedString.Key.biteLink, .biteWrittenLink] {
            storage.enumerateAttribute(key, in: all) { value, range, _ in
                if value != nil { starts.append(range.location) }
            }
        }
        var links: [PageLink] = []
        for start in starts.sorted() where !links.contains(where: { NSLocationInRange(start, $0.range) }) {
            if let link = link(at: start) { links.append(link) }
        }
        return links
    }

    /// The link the selection is within, or a caret strictly inside, where no other can go. A
    /// caret at either end of one is where a new link goes.
    private func linkAround(_ selection: NSRange) -> PageLink? {
        guard let link = link(at: selection.location) else { return nil }
        guard selection.length > 0 else { return link.range.location < selection.location ? link : nil }
        return NSMaxRange(selection) <= NSMaxRange(link.range) ? link : nil
    }

    /// Makes `link`'s text say `text` and go to `destination`, as one edit. Text that says its
    /// own address stays plain text where it shows as a link anyway, and so does text whose
    /// destination is taken away. A new link given no destination is its text, as text: what the
    /// page showed as it was typed. With neither, the link's text goes. Nothing happens if the
    /// page has changed there since, or if there's nothing to change.
    func setLink(_ link: PageLink, text: String, destination: String) {
        finishComposing()
        guard isStill(link) else { return }
        let original = storage.attributedSubstring(from: link.range)
        let replacement = linkText(for: link, original: original, at: link.range, text: text, destination: destination)
        guard !replacement.isEqual(to: original) else { return }
        replace(link.range, with: replacement, selection: NSRange(location: link.range.location + replacement.length, length: 0))
    }

    /// What `setLink` puts in place of `link`'s text, `original`, which is at `range`: `text` going
    /// to `destination`, with no text the address, and with neither nothing. The page shows this
    /// as it's typed (`previewLink`), so it's all that's put in: nothing shows that doesn't stay.
    private func linkText(for link: PageLink, original: NSAttributedString, at range: NSRange,
                          text: String, destination: String) -> NSMutableAttributedString {
        let typed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.isEmpty ? typed : text
        // Kept in full, as any app reading the Markdown needs it.
        let destination = LinkDetector.destination(forTyped: typed)
        let replacement = text == link.text && original.length > 0
            ? NSMutableAttributedString(attributedString: original)
            : newText(text, at: range)
        let all = NSRange(location: 0, length: replacement.length)
        if destination.isEmpty || (showsAsAddress(text, at: range) && LinkDetector.destination(of: text) == destination) {
            replacement.removeAttribute(.biteLink, range: all)
            // Taken off a link, an address written out stays off. Typed for a new one, with no
            // address to go to, it's text, and shows as a link by its own text as any does.
            if destination.isEmpty, !link.isNew { keepAddressesPlain(in: replacement, at: range) }
        } else {
            replacement.addAttribute(.biteLink, value: destination, range: all)
        }
        return replacement
    }

    /// `text` to put in place of `range`, in the style of the text there, or of what's typed at
    /// the caret.
    private func newText(_ text: String, at range: NSRange) -> NSMutableAttributedString {
        let inline = range.length > 0 ? inlineStyle(at: range.location) : typingStyle(at: range.location)
        var attributes = lineBreakAttributes(for: block(of: lineRange(at: range.location)))
        attributes[.biteInline] = inline.rawValue
        return NSMutableAttributedString(string: text, attributes: attributes)
    }

    // MARK: Links shown as they're typed

    /// A link being changed in the format bar, shown on the page as it's typed: its text as it
    /// was, the selection then, and the text shown in its place, and where.
    private var linkPreview: (link: PageLink, original: NSAttributedString, selection: NSRange,
                              shown: String, range: NSRange)?

    /// Shows on the page what `setLink` would make of `link` with `text` and `destination`, as
    /// they're typed in the format bar, so the page's text follows the bar's. None of it is an
    /// edit of its own, to undo: it's put back (`endLinkPreview`) before the link is changed for
    /// good, in one edit. Says where the text shown is.
    @discardableResult
    func previewLink(_ link: PageLink, text: String, destination: String) -> NSRange {
        if linkPreview == nil {
            guard isStill(link) else { return link.range }
            linkPreview = (link, storage.attributedSubstring(from: link.range), clamp(textView.selectedRange), link.text, link.range)
        }
        guard var preview = linkPreview, preview.link == link, textIsStill(preview.shown, at: preview.range) else { return link.range }
        let shown = linkText(for: link, original: preview.original, at: preview.range, text: text, destination: destination)
        // Nothing for nothing, as at the caret before anything's typed.
        guard shown.length > 0 || preview.range.length > 0 else { return preview.range }
        replaceUnrecorded(preview.range, with: shown, selection: NSRange(location: preview.range.location + shown.length, length: 0))
        preview.shown = shown.string
        preview.range.length = shown.length
        linkPreview = preview
        return preview.range
    }

    /// Puts back the text of a link shown as it was being typed (`previewLink`), and the
    /// selection then.
    func endLinkPreview() {
        guard let preview = linkPreview else { return }
        linkPreview = nil
        // Changed from elsewhere meanwhile, as iCloud may, it's left as it is.
        guard textIsStill(preview.shown, at: preview.range) else { return }
        replaceUnrecorded(preview.range, with: preview.original, selection: preview.selection)
    }

    /// Whether `location` is in the text shown for a link as it's typed.
    func isInLinkPreview(_ location: Int) -> Bool {
        guard let preview = linkPreview else { return false }
        return NSLocationInRange(location, preview.range)
    }

    /// Replaces `range` with no undo step. Turning registration off in UIKit's own undo manager
    /// for it threw: UIKit turned it back on as the text changed.
    private func replaceUnrecorded(_ range: NSRange, with replacement: NSAttributedString, selection: NSRange) {
        replace(range, with: replacement, selection: selection, recordsUndo: false)
    }

    /// Whether `text`, put in for `range`, would show as a link on its own, an address written
    /// out. Right after a letter, as typed on the end of a word, it wouldn't.
    private func showsAsAddress(_ text: String, at range: NSRange) -> Bool {
        guard LinkDetector.isAddress(text) else { return false }
        let content = contentRange(of: lineRange(at: range.location))
        let line = NSMutableString(string: string.substring(with: NSRange(location: content.lowerBound, length: content.count)))
        let local = NSRange(location: range.location - content.lowerBound, length: range.length)
        line.replaceCharacters(in: local, with: text)
        return LinkDetector.addresses(in: line as String).contains(local.location..<(local.location + (text as NSString).length))
    }

    /// Takes the link off `link`'s text, which stays as it is, an address written out too.
    func removeLink(_ link: PageLink) {
        finishComposing()
        guard isStill(link), !link.isNew else { return }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: link.range))
        replacement.removeAttribute(.biteLink, range: NSRange(location: 0, length: replacement.length))
        keepAddressesPlain(in: replacement, at: link.range)
        replace(link.range, with: replacement, selection: NSRange(location: NSMaxRange(link.range), length: 0))
    }

    /// The page still has `link`'s text where it was.
    private func isStill(_ link: PageLink) -> Bool {
        NSMaxRange(link.range) <= storage.length - 1 && string.substring(with: link.range) == link.text
    }

    /// Ticks or unticks the to-do at `location`, and says which: nil if there's no to-do there.
    /// The page stays where it is: the caret hasn't moved, and bringing it into view took the
    /// page away from the box clicked (user, 2026-10-05).
    @discardableResult
    func toggleTodo(at location: Int) -> Bool? {
        finishComposing()
        let line = lineRange(at: location)
        guard block(of: line).kind == .todo else { return nil }
        setBlocks(of: [line], scrollsToCaret: false) { $0.isChecked.toggle() }
        return block(of: lineRange(at: location)).isChecked
    }

    // MARK: Clipboard

    /// The Markdown of a copy made in Bite, while the pasteboard still holds it.
    static var copiedMarkdown: String? {
        Clipboard.markdown
    }

    /// Copies the selection as Markdown, so it pastes cleanly anywhere. Code on its own copies as
    /// just the code, for a terminal or another editor, where a fence would be in the way; the
    /// Markdown goes along for pasting back into Bite, where it's code again.
    func copySelection() {
        let selection = clamp(textView.selectedRange)
        guard selection.length > 0 else { return }
        let copied = copiedText(in: selection)
        guard let code = copied.code else {
            Clipboard.string = copied.markdown
            return
        }
        Clipboard.set(code, markdown: copied.markdown)
    }

    /// `range` as Markdown, and code on its own as just the code. Part of a line, with no line
    /// break in it, is just its text, as in Notion: a word copied from a list item or a heading
    /// and pasted into a sentence used to bring the item's `- ` or the heading's `# ` along.
    private func copiedText(in range: NSRange) -> (markdown: String, code: String?) {
        var document = AttributedDocument.document(from: storage, in: range)
        if !string.substring(with: range).contains("\n"), let block = document.blocks.first, block.kind != .code {
            document.blocks = [Block(kind: .paragraph, runs: block.runs)]
        }
        var markdown = MarkdownSerializer.markdown(from: document)
        if markdown.hasSuffix("\n") { markdown.removeLast() }
        guard document.blocks.allSatisfy({ $0.kind == .code }) else { return (markdown, nil) }
        return (markdown, document.blocks.map(\.text).joined(separator: "\n"))
    }

    /// Pastes as Markdown: plain text stays plain, Markdown syntax turns into formatting. Into a
    /// code block text goes as it is, a line of code per line, since `#`, `-` or `*` there are code.
    func paste(_ text: String) {
        guard !text.isEmpty else { return }
        finishComposing()
        let selection = clamp(textView.selectedRange)
        // An address pasted onto text links the text to it, as in Notion. The text stays.
        if selection.length > 0, LinkDetector.isAddress(text), !string.substring(with: selection).contains("\n"),
           ![.code, .divider].contains(block(of: lineRange(at: selection.location)).kind) {
            let linked = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection))
            linked.addAttribute(.biteLink, value: LinkDetector.destination(forTyped: text),
                                range: NSRange(location: 0, length: linked.length))
            replace(selection, with: linked, selection: NSRange(location: NSMaxRange(selection), length: 0))
            return
        }
        // One line pasted among text goes in as text, markers and all: `- `, `# ` or `1. ` only
        // start a block on a line of their own. Bold, italics and code still come through.
        let isOneLine = !MarkdownParser.normalizedLineBreaks(text).contains("\n")
        if isOneLine, pasteIntoInlineCode(text, over: selection) { return }
        let document = isOneLine && hasText(besides: selection) ? MarkdownParser.parseText(text) : MarkdownParser.parse(text)
        guard !document.blocks.isEmpty else { return }
        let current = block(of: lineRange(at: selection.location))
        let inserted: NSMutableAttributedString
        if current.kind == .code {
            // Code copied with its fence, from Bite or a chat, goes in without the fence.
            let isFenced = document.blocks.allSatisfy { $0.kind == .code }
            let code = isFenced ? document.blocks.map(\.text).joined(separator: "\n") : MarkdownParser.normalizedLineBreaks(text)
            inserted = NSMutableAttributedString(string: code, attributes: lineBreakAttributes(for: current))
        } else {
            var blocks = document.blocks
            // A list pasted into a list item nests where the item is.
            if current.kind.isList {
                for index in blocks.indices {
                    guard blocks[index].kind.isList else { break }
                    blocks[index].indent += current.indent
                }
            }
            inserted = AttributedDocument.attributedString(blocks: blocks, terminated: false)
            if isOneLine { continueLink(over: inserted, at: selection) }
            // Plain text pasted into a list item stays in that item.
            if document.blocks[0].kind == .paragraph, current.kind != .paragraph {
                let firstLineEnd = (inserted.string as NSString).range(of: "\n").location
                let firstLine = NSRange(location: 0, length: firstLineEnd == NSNotFound ? inserted.length : firstLineEnd)
                inserted.addAttributes(current.dictionary, range: firstLine)
            }
        }
        let caret = NSRange(location: selection.location + inserted.length, length: 0)
        if string.substring(with: selection).contains("\n") {
            replaceAcrossLines(selection, with: inserted, joinedLineKeeps: nil, selection: caret)
        } else {
            replace(selection, with: inserted, selection: caret)
        }
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    /// Into inline code a line goes in as it is, as typing puts it there: code holds no
    /// Markdown. Code copied from Bite comes as Markdown in backticks, which go.
    private func pasteIntoInlineCode(_ text: String, over selection: NSRange) -> Bool {
        let block = block(of: lineRange(at: selection.location))
        guard block.kind != .code, !string.substring(with: selection).contains("\n") else { return false }
        let style = selection.length > 0 ? inlineStyle(at: selection.location) : typingStyle(at: selection.location)
        guard style.contains(.code) else { return false }
        let runs = MarkdownParser.parseText(text).blocks.first?.runs ?? []
        let isCode = !runs.isEmpty && runs.allSatisfy { $0.style.contains(.code) }
        var attributes = block.dictionary
        attributes[.biteInline] = style.rawValue
        let inserted = NSMutableAttributedString(string: isCode ? runs.map(\.text).joined() : text, attributes: attributes)
        continueLink(over: inserted, at: selection)
        replace(selection, with: inserted, selection: NSRange(location: selection.location + inserted.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange)
        return true
    }

    /// Text pasted into a link's text is more of it, as typed text is (see `linkContinued`):
    /// pasted strictly inside it, or in place of text all in it. Pasted text's own links stay
    /// theirs, as the inner of two links wins. Pasted in, it split the link in two.
    private func continueLink(over inserted: NSMutableAttributedString, at selection: NSRange) {
        guard let link = linkContinued(by: selection), !inserted.string.contains("\n") else { return }
        inserted.enumerateAttribute(.biteLink, in: NSRange(location: 0, length: inserted.length)) { value, range, _ in
            if value == nil { inserted.addAttribute(.biteLink, value: link, range: range) }
        }
    }

    // MARK: Drag and drop

    #if canImport(UIKit)
    /// Where the text being dragged out of this page is, and what it was, while the drag lasts.
    private var dragged: (range: NSRange, text: String)?

    /// Left to UIKit, a drop moved the text straight in the text storage: the editor never heard
    /// of it, so it was neither styled nor saved, there was no undo, and text dropped at the start
    /// of a line turned the line into the kind it came from. So Bite makes the drop itself.
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        let proposal = drop.suggestedProposal.copy() as? UITextDropProposal ?? drop.suggestedProposal
        proposal.dropPerformer = .delegate
        proposal.useFastSameViewOperations = false
        return proposal
    }

    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, willPerformDrop drop: UITextDropRequest) {
        let location = textView.offset(from: textView.beginningOfDocument, to: drop.dropPosition)
        if drop.isSameView, let dragged, textIsStill(dragged.text, at: dragged.range) {
            move(dragged.range, to: location)
            return
        }
        _ = drop.dropSession.loadObjects(ofClass: String.self) { [weak self] strings in
            MainActor.assumeIsolated {
                guard let self, !strings.isEmpty else { return }
                self.textView.selectedRange = self.clamp(NSRange(location: location, length: 0))
                self.paste(strings.joined(separator: "\n"))
            }
        }
    }

    func textDraggableView(_ textDraggableView: UIView & UITextDraggable, itemsForDrag dragRequest: UITextDragRequest) -> [UIDragItem] {
        let start = textView.offset(from: textView.beginningOfDocument, to: dragRequest.dragRange.start)
        let end = textView.offset(from: textView.beginningOfDocument, to: dragRequest.dragRange.end)
        let range = clamp(NSRange(location: start, length: end - start))
        dragged = (range, string.substring(with: range))
        return dragRequest.suggestedItems
    }

    func textDraggableView(_ textDraggableView: UIView & UITextDraggable, dragSessionDidEnd session: UIDragSession,
                           with operation: UIDropOperation) {
        dragged = nil
    }
    #endif

    /// Text dragged within the page moves as if cut and pasted where it's dropped, and one undo
    /// puts it back. Whole lines move as lines: dropped at the start of a line they go in above
    /// it, and anywhere else on it, below it.
    func move(_ range: NSRange, to location: Int) {
        finishComposing()
        var source = clamp(range)
        guard source.length > 0, location < source.location || location > NSMaxRange(source) else { return }
        // Lines selected from the start of one to the end of another are whole lines too: the
        // selection shows no line break after the last one, and the page's last can't be selected.
        if isLineStart(source.location), string.substring(with: source).contains("\n"), !isLineStart(NSMaxRange(source)),
           NSMaxRange(source) < storage.length, string.character(at: NSMaxRange(source)) == 0x0A {
            guard NSMaxRange(source) + 1 < storage.length else {
                moveLastLines(source, to: location)
                return
            }
            source.length += 1
        }
        let isWholeLines = isLineStart(source.location) && isLineStart(NSMaxRange(source))
        if isWholeLines {
            // Dropped just above or below themselves, the lines stay where they are.
            let lineStart = isLineStart(location) ? location : NSMaxRange(lineRange(at: location))
            guard lineStart != source.location, lineStart != NSMaxRange(source) else { return }
        }
        let lines = storage.attributedSubstring(from: source)
        let markdown = copiedText(in: source).markdown
        if string.substring(with: source).contains("\n") {
            joinLines(deleting: source)
        } else {
            replace(source, with: NSAttributedString(), selection: NSRange(location: source.location, length: 0))
        }
        var target = location > source.location ? location - source.length : location
        guard isWholeLines else {
            textView.selectedRange = clamp(NSRange(location: target, length: 0))
            paste(markdown)
            return
        }
        if !isLineStart(target) { target = NSMaxRange(lineRange(at: target)) }
        replace(NSRange(location: target, length: 0), with: lines, selection: NSRange(location: target + lines.length - 1, length: 0))
    }

    /// The page's last lines, whose final line break stays where it is: they go with the line
    /// break before them, and get one of their own where they land.
    private func moveLastLines(_ source: NSRange, to location: Int) {
        guard source.location > 0, location < source.location - 1 else { return }
        let lines = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: source))
        lines.append(NSAttributedString(string: "\n", attributes: lineBreakAttributes(for: block(of: lineRange(at: NSMaxRange(source) - 1)))))
        joinLines(deleting: NSRange(location: source.location - 1, length: source.length + 1))
        let target = isLineStart(location) ? location : NSMaxRange(lineRange(at: location))
        replace(NSRange(location: target, length: 0), with: lines, selection: NSRange(location: target + lines.length - 1, length: 0))
    }

    // MARK: Editing primitives

    /// Replaces `range` and registers the inverse with the text view's undo manager, unless
    /// `recordsUndo` is false. `undo` overrides what undo restores; by default it's the text that
    /// was there. Unless `scrollsToCaret` is false, the caret's brought into view after, and
    /// after undoing it.
    private func replace(_ range: NSRange, with replacement: NSAttributedString, selection: NSRange,
                         undo: (text: NSAttributedString, selection: NSRange)? = nil, recordsUndo: Bool = true,
                         scrollsToCaret: Bool = true) {
        // Undo puts back whole lines: those the edit touches, and the line after one that ends
        // at a line start, which the edit's last line may join. Restyling after the edit gives
        // the rest of each of those lines the kind of its first character, and an undo of just
        // the replaced text left that behind: undoing a list pasted onto an empty line left an
        // empty numbered item.
        let lines = linesTouched(by: range)
        let previous = NSMutableAttributedString(attributedString: storage.attributedSubstring(
            from: NSRange(location: lines.location, length: range.location - lines.location)))
        previous.append(undo?.text ?? storage.attributedSubstring(from: range))
        previous.append(storage.attributedSubstring(from: NSRange(location: NSMaxRange(range), length: NSMaxRange(lines) - NSMaxRange(range))))
        let previousSelection = undo?.selection ?? textView.selectedRange
        let replacedRange = NSRange(location: range.location, length: replacement.length)
        let linesAfter = NSRange(location: lines.location, length: lines.length - range.length + replacement.length)
        let textAfter = string.substring(with: NSRange(location: lines.location, length: range.location - lines.location))
            + replacement.string
            + string.substring(with: NSRange(location: NSMaxRange(range), length: NSMaxRange(lines) - NSMaxRange(range)))
        // The keyboard asks before a backspace, but the text view may then handle it here
        // instead; whatever it asked about isn't going to happen.
        pendingEdit = nil
        if recordsUndo {
            textView.undoManager?.registerUndo(withTarget: self) { controller in
                MainActor.assumeIsolated {
                    guard controller.textIsStill(textAfter, at: linesAfter) else { return }
                    controller.replace(linesAfter, with: previous, selection: previousSelection, scrollsToCaret: scrollsToCaret)
                }
            }
        }
        #if canImport(UIKit)
        // Tell the keyboard the text changed under it, so autocorrect and predictions work from
        // the new text rather than what was typed before the shortcut.
        textView.inputDelegate?.textWillChange(textView)
        #else
        // Typing after this starts an undo step of its own, not one with the typing before it.
        textView.breakUndoCoalescing()
        #endif
        isApplyingEdit = true
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        isApplyingEdit = false
        // Stepped over a divider here too: UIKit says nothing when the selection is set to what
        // it was, though the line under it may have become a divider, as when lines were
        // dragged to where the caret was.
        textView.selectedRange = stepOverDivider(clamp(selection))
        #if canImport(UIKit)
        textView.inputDelegate?.textDidChange(textView)
        #endif
        contentDidChange(in: replacedRange, scrollsToCaret: scrollsToCaret)
        tellKeyboardOnceItsDone()
    }

    /// Whether `range` still holds `text`, as it did right after the edit an undo step takes
    /// back. It may not: UIKit loses the undo step of text just typed when an input method
    /// composes over a selection that takes it in (a plain `UITextView` does the same), and the
    /// steps before it then point at text that has moved. Such a step is let go rather than
    /// applied where it no longer fits, which split a line in two.
    private func textIsStill(_ text: String, at range: NSRange) -> Bool {
        NSMaxRange(range) <= storage.length && string.substring(with: range) == text
    }

    /// The lines an edit of `range` touches, from the start of its first to the end of its last,
    /// and the line after it when it ends at a line start.
    private func linesTouched(by range: NSRange) -> NSRange {
        guard storage.length > 0 else { return range }
        var lines = string.paragraphRange(for: NSRange(location: min(range.location, storage.length), length: range.length))
        if NSMaxRange(range) < storage.length {
            lines = NSUnionRange(lines, lineRange(at: NSMaxRange(range)))
        }
        return NSUnionRange(lines, range)
    }

    private var keyboardNeedsTelling = false

    /// The keyboard works out its shift state from the text before the caret. An edit made while
    /// the keyboard waits on its own key (Return, backspace) happens under it, and it doesn't
    /// look again when that edit was a "no" to what it asked: after a backspace joined a line
    /// back up, the next letter came out capitalized. So it's told again when it's done.
    private func tellKeyboardOnceItsDone() {
        #if canImport(UIKit)
        guard textView.isFirstResponder, !keyboardNeedsTelling else { return }
        keyboardNeedsTelling = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            keyboardNeedsTelling = false
            guard textView.isFirstResponder, !textView.isComposing else { return }
            textView.inputDelegate?.selectionWillChange(textView)
            textView.inputDelegate?.selectionDidChange(textView)
        }
        #endif
    }

    private func setBlocks(of lines: [NSRange], scrollsToCaret: Bool = true, _ change: (inout BlockAttributes) -> Void) {
        guard let first = lines.first, let last = lines.last else { return }
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        for line in lines {
            let local = NSRange(location: line.location - range.location, length: line.length)
            var block = BlockAttributes(replacement.attributes(at: local.location, effectiveRange: nil))
            change(&block)
            block.indent = block.kind.isList ? max(0, block.indent) : 0
            replacement.addAttributes(block.dictionary, range: local)
        }
        replace(range, with: replacement, selection: textView.selectedRange, scrollsToCaret: scrollsToCaret)
    }

    /// `withinLine` is for typing that stays inside one line. That can't change any line's kind,
    /// level or number, so those aren't worked out again, which took longer than a frame on
    /// every keystroke in a long page.
    private func contentDidChange(in range: NSRange, withinLine: Bool = false, scrollsToCaret: Bool = true) {
        ensureTrailingNewline()
        if withinLine {
            takeLineAttributes(range)
            restyleTyped(range)
        } else {
            restyle(range)
            updateStructure(around: range)
        }
        updateTypingAttributes()
        scheduleReport()
        // Edits made here (list continuation, shortcuts) don't go through UIKit's typing path,
        // so nothing else would bring the caret into view.
        if scrollsToCaret, textView.isFirstResponder {
            textView.requestCaretScroll()
        }
    }

    /// Text typed into a line takes the line's number and place among its neighbours from a
    /// character of the line that was there before it: the one after the typed text, which is
    /// at worst the line break. (Taking them from the line break always once spread a wrong
    /// number over a whole line; line breaks now always match their line, but typed text still
    /// shouldn't be where the line's values come from.)
    private func takeLineAttributes(_ range: NSRange) {
        let line = lineRange(at: range.location)
        let source = min(NSMaxRange(range), NSMaxRange(line) - 1)
        for key in [NSAttributedString.Key.biteOrdinal, .biteShownStyle, .biteRunPosition] {
            if let value = storage.attribute(key, at: source, effectiveRange: nil) {
                storage.addAttribute(key, value: value, range: range)
            }
        }
    }

    // MARK: Changes UIKit makes on its own

    /// Text UIKit changed without asking first or saying so after, as it did with drops until
    /// Bite made them itself, and as Writing Tools may: the page went unsaved and its lines
    /// unstyled. It's put right on the next turn of the run loop, once the change is done, as if
    /// it had been typed. A change UIKit does say it made, an undo say, is put right when it
    /// says so.
    private var unannouncedEdit: UnannouncedEdit?

    private struct UnannouncedEdit {
        /// All the text that changed, where it is now.
        var range: NSRange
        /// The text that went in, where it is now.
        var insertions: [NSRange] = []

        init(_ edited: NSRange) {
            range = edited
            if edited.length > 0 { insertions = [edited] }
        }

        /// Takes in another change, which put `edited.length` characters where there were
        /// `edited.length - delta`.
        mutating func add(_ edited: NSRange, changeInLength delta: Int) {
            follow(edited, changeInLength: delta)
            range = NSUnionRange(range, edited)
            if edited.length > 0 { insertions.append(edited) }
        }

        /// Keeps the ranges where their text is through a change made by the editor itself.
        mutating func follow(_ edited: NSRange, changeInLength delta: Int) {
            range = Self.moved(range, by: edited, changeInLength: delta)
            insertions = insertions.map { Self.moved($0, by: edited, changeInLength: delta) }
        }

        /// Where `range` is after the change: moved along if it comes after it, stretched to
        /// take it in if they meet.
        static func moved(_ range: NSRange, by edited: NSRange, changeInLength delta: Int) -> NSRange {
            if NSMaxRange(range) < edited.location { return range }
            if range.location > NSMaxRange(edited) - delta {
                return NSRange(location: range.location + delta, length: range.length)
            }
            let start = min(range.location, edited.location)
            return NSRange(location: start, length: max(NSMaxRange(range) + delta, NSMaxRange(edited)) - start)
        }
    }

    @objc private func storageWillProcessEditing(_ notification: Notification) {
        guard storage.editedMask.contains(.editedCharacters) else { return }
        // Whatever changed the text, typing or another device, found text has had its moment.
        // Its light goes at once, fading or not: left to fade, it stayed where the text had been.
        textView.hideFound(.atOnce)
        let edited = storage.editedRange
        let delta = storage.changeInLength
        if isApplyingEdit {
            unannouncedEdit?.follow(edited, changeInLength: delta)
        } else if unannouncedEdit != nil {
            unannouncedEdit?.add(edited, changeInLength: delta)
        } else {
            unannouncedEdit = UnannouncedEdit(edited)
            DispatchQueue.main.async { [weak self] in self?.settleUnannouncedEdit() }
        }
    }

    /// Restyles, and reports, text UIKit changed on its own. Text still being composed, or
    /// being rewritten by Writing Tools, is left until that's done.
    private func settleUnannouncedEdit() {
        guard let edit = unannouncedEdit, !isApplyingEdit, !textView.isComposing,
              !textView.isWritingToolsActive else { return }
        unannouncedEdit = nil
        ensureTrailingNewline()
        // Text put in at the start of a line, with no line break of its own, joins that line as
        // typed text does. It may come with the attributes of the line it was taken from, and
        // the first character of a line decides what the line is.
        isApplyingEdit = true
        storage.beginEditing()
        for insertion in edit.insertions {
            let inserted = clampToPage(insertion)
            guard inserted.length > 0, NSMaxRange(inserted) < storage.length, isLineStart(inserted.location),
                  !string.substring(with: inserted).contains("\n") else { continue }
            let line = BlockAttributes(storage.attributes(at: NSMaxRange(inserted), effectiveRange: nil))
            storage.addAttributes(line.dictionary, range: inserted)
        }
        storage.endEditing()
        isApplyingEdit = false
        contentDidChange(in: clampToPage(edit.range))
    }

    #if canImport(UIKit)
    func textViewWritingToolsWillBegin(_ textView: UITextView) {
        self.textView.writingToolsWillBegin()
        onWritingToolsChange?(true)
    }

    func textViewWritingToolsDidEnd(_ textView: UITextView) {
        self.textView.writingToolsDidEnd()
        onWritingToolsChange?(false)
        settleUnannouncedEdit()
    }
    #else
    func textViewWritingToolsDidEnd(_ textView: NSTextView) {
        settleUnannouncedEdit()
    }

    @objc private func undoManagerDidChange(_ notification: Notification) {
        settleUnannouncedEdit()
        // AppKit selects the text an undo puts back or a redo types again. It's left as a caret
        // after it, as on the phone; a selection that was there before, as for a bold undone,
        // stays.
        let selection = textView.selectedRange
        if selection.length > 0, selection != selectionBeforeUndo {
            textView.setSelectedRange(NSRange(location: NSMaxRange(selection), length: 0))
        }
    }

    private var selectionBeforeUndo: NSRange?

    @objc private func undoManagerWillChange(_ notification: Notification) {
        selectionBeforeUndo = textView.selectedRange
    }
    #endif

    private func clampToPage(_ range: NSRange) -> NSRange {
        let location = min(max(0, range.location), storage.length)
        return NSRange(location: location, length: max(0, min(NSMaxRange(range), storage.length) - location))
    }

    // MARK: Reporting changes

    /// A change is reported once typing pauses, and the Markdown is worked out off the main
    /// thread: reading a long page back on every keystroke, or even at every pause, made typing
    /// stutter. Whether the page is empty goes out at once, since the dot bar shows it.
    private var pendingReport: Task<Void, Never>?
    private var reportedEmpty: Bool?
    /// Bumped by every change; a report says which one it's up to date with. A report worked out
    /// in the background is dropped if a newer one got there first.
    private var changeCount = 0
    private var reportedCount = 0
    /// Typing that never pauses is still reported this often, so it's saved, and shows on the
    /// other devices as it goes.
    private var reportDeadline: ContinuousClock.Instant?

    private func scheduleReport() {
        changeCount += 1
        let isEmpty = pageIsEmpty
        if isEmpty != reportedEmpty {
            reportedEmpty = isEmpty
            onEmptyChange?(isEmpty)
        }
        let now = ContinuousClock.now
        let deadline = reportDeadline ?? now + .seconds(1)
        reportDeadline = deadline
        pendingReport?.cancel()
        pendingReport = Task { [weak self] in
            try? await Task.sleep(for: min(.milliseconds(250), deadline - now))
            guard !Task.isCancelled else { return }
            self?.reportInBackground()
        }
    }

    private func reportInBackground() {
        pendingReport = nil
        reportDeadline = nil
        let count = changeCount
        // A copy to read on another thread; it shares the text's storage and takes a moment.
        let snapshot = PageSnapshot(text: NSAttributedString(attributedString: storage))
        Task.detached(priority: .utility) { [weak self] in
            let markdown = snapshot.markdown()
            await self?.deliver(markdown, upTo: count)
        }
    }

    private func deliver(_ markdown: String, upTo count: Int) {
        guard count > reportedCount else { return }
        reportedCount = count
        onChange?(markdown)
    }

    /// Reports straight away any change not reported yet, as the page is saved, copied or cleared.
    func reportPendingChange() {
        guard changeCount > reportedCount else { return }
        pendingReport?.cancel()
        pendingReport = nil
        reportDeadline = nil
        deliver(PageSnapshot(text: storage).markdown(), upTo: changeCount)
    }

    /// As in `BiteDocument.isEmpty`: nothing but empty paragraphs.
    private var pageIsEmpty: Bool {
        var position = 0
        while position < storage.length {
            let line = lineRange(at: position)
            if block(of: line).kind != .paragraph || !contentRange(of: line).isEmpty { return false }
            position = NSMaxRange(line)
        }
        return true
    }

    private func ensureTrailingNewline() {
        guard string.length == 0 || string.character(at: string.length - 1) != 0x0A else { return }
        let last = storage.length > 0 ? BlockAttributes(storage.attributes(at: storage.length - 1, effectiveRange: nil)) : BlockAttributes()
        let selection = textView.selectedRange
        isApplyingEdit = true
        storage.append(NSAttributedString(string: "\n", attributes: lineBreakAttributes(for: last)))
        isApplyingEdit = false
        textView.selectedRange = clamp(selection)
    }

    // MARK: Styling

    /// Re-derives display attributes for every line touching `range`. A line's block attributes
    /// come from its first character, so merged or split lines settle on one kind.
    private func restyle(_ range: NSRange) {
        let length = storage.length
        guard length > 0 else { return }
        let location = min(range.location, length - 1)
        let clipped = NSRange(location: location, length: max(0, min(NSMaxRange(range), length) - location))
        let lines = string.paragraphRange(for: clipped)
        storage.beginEditing()
        var position = lines.location
        while position < NSMaxRange(lines) {
            let line = lineRange(at: position)
            restyleLine(line)
            position = NSMaxRange(line)
        }
        storage.endEditing()
    }

    private func restyleLine(_ line: NSRange) {
        guard line.length > 0 else { return }
        var block = block(of: line)
        if block.kind == .divider, !contentRange(of: line).isEmpty { block.kind = .paragraph }
        if !block.kind.isList { block.indent = 0 }
        if block.kind != .todo { block.isChecked = false }
        if block.kind != .ordered {
            block.number = nil
            block.numberStyle = nil
        }
        if block.kind != .code { block.language = "" }
        storage.addAttributes(block.dictionary, range: line)
        if block.kind == .code {
            storage.addAttribute(.biteInline, value: 0, range: line)
            storage.removeAttribute(.biteLink, range: line)
        }
        // A line break holds no text, so it never takes an inline style, whatever came with it:
        // text typed or pasted across lines, a style set over lines. Styled, it drew a
        // strikethrough past the end of the line, and an empty line left behind in bold or
        // italic kept the wrong font.
        if let lastCharacter = line.length > 0 ? NSMaxRange(line) - 1 : nil, string.character(at: lastCharacter) == 0x0A {
            storage.addAttribute(.biteInline, value: 0, range: NSRange(location: lastCharacter, length: 1))
            storage.removeAttribute(.biteLink, range: NSRange(location: lastCharacter, length: 1))
        }
        styleText(in: line, as: block)
        markWrittenLinks(inLine: line, as: block)
    }

    /// Text typed into a line took the line's block attributes (`apply`) and its place among its
    /// neighbours (`takeLineAttributes`), so the rest of the line stays as it was and only the new
    /// text needs its look. Restyling the whole line on every keystroke took three frames in a
    /// long paragraph.
    private func restyleTyped(_ range: NSRange) {
        guard range.length > 0 else { return }
        let line = lineRange(at: range.location)
        let block = block(of: line)
        guard block.kind != .divider, NSMaxRange(range) < NSMaxRange(line) else {
            restyle(range)
            return
        }
        storage.beginEditing()
        styleText(in: range, as: block)
        markWrittenLinks(inLine: line, as: block)
        storage.endEditing()
    }

    /// The display attributes of `range`, on a line of kind `block`, from its inline styles.
    private func styleText(in range: NSRange, as block: BlockAttributes) {
        let runPosition = RunPosition(rawValue: storage.attribute(.biteRunPosition, at: range.location, effectiveRange: nil) as? Int ?? 0) ?? .single
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.strikethroughColor, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.underlineColor, range: range)
        for (run, inline) in inlineRuns(in: storage, range: range) {
            storage.addAttributes(displayAttributes(for: block, inline: inline, runPosition: runPosition), range: run)
            if inline.contains(.italic), block.kind != .code {
                slantTextWithoutItalics(in: run)
            }
        }
        guard block.kind != .code else { return }
        storage.enumerateAttribute(.biteLink, in: range) { link, linkRange, _ in
            // An empty link keeps an address from being one, and it looks like the text around it.
            if let link = link as? String, !link.isEmpty {
                storage.addAttributes(theme.linkAttributes(for: block), range: linkRange)
            }
        }
    }

    /// Addresses written out in a line show as links (see `LinkDetector`), except in code or in
    /// a link's own text. Found again whenever the line changes: one that's no longer an
    /// address, typed on into a word, goes back to looking like the text around it.
    private func markWrittenLinks(inLine line: NSRange, as block: BlockAttributes) {
        var previous: [NSRange] = []
        storage.enumerateAttribute(.biteWrittenLink, in: line) { value, range, _ in
            if value != nil { previous.append(range) }
        }
        let found = block.kind == .code ? [] : writtenLinks(inLine: line, of: storage)
        guard !previous.isEmpty || !found.isEmpty else { return }
        storage.removeAttribute(.biteWrittenLink, range: line)
        for range in previous where !found.contains(range) {
            styleText(in: range, as: block)
        }
        for range in found {
            storage.addAttribute(.biteWrittenLink, value: string.substring(with: range), range: range)
            storage.addAttributes(theme.linkAttributes(for: block), range: range)
        }
    }

    /// The addresses written out in `line` of `text`, outside code and links.
    private func writtenLinks(inLine line: NSRange, of text: NSAttributedString) -> [NSRange] {
        let content = AttributedDocument.contentRange(of: line, in: text.string as NSString)
        guard content.count >= 4 else { return [] }
        let lineText = (text.string as NSString).substring(with: NSRange(location: content.lowerBound, length: content.count))
        return LinkDetector.addresses(in: lineText).compactMap { address in
            let range = NSRange(location: content.lowerBound + address.lowerBound, length: address.count)
            var isText = true
            text.enumerateAttributes(in: range) { attributes, _, stop in
                let inline = InlineStyle(rawValue: attributes[.biteInline] as? Int ?? 0)
                if inline.contains(.code) || attributes[.biteLink] != nil {
                    isText = false
                    stop.pointee = true
                }
            }
            return isText ? range : nil
        }
    }

    /// What a line of each kind and style looks like. Every line of a page is styled when it
    /// loads, and making fonts and paragraph styles over again for each one took most of the time.
    private struct DisplayKey: Hashable {
        let kind: BlockKind
        let indent: Int
        let isChecked: Bool
        let inline: InlineStyle
        let runPosition: RunPosition
    }

    private var displayAttributesCache: [DisplayKey: [NSAttributedString.Key: Any]] = [:]

    private func displayAttributes(for block: BlockAttributes, inline: InlineStyle, runPosition: RunPosition) -> [NSAttributedString.Key: Any] {
        // Only what the theme looks at: indents for lists, a code line's place in its block.
        let key = DisplayKey(kind: block.kind, indent: block.kind.isList ? block.indent : 0,
                             isChecked: block.kind == .todo && block.isChecked, inline: inline,
                             runPosition: block.kind == .code ? runPosition : .single)
        if let attributes = displayAttributesCache[key] { return attributes }
        let attributes = theme.displayAttributes(for: block, inline: inline, runPosition: runPosition)
        displayAttributesCache[key] = attributes
        return attributes
    }

    /// Chinese, Japanese and Korean fonts have no italics, so italic text in those scripts came
    /// out upright. Those characters get a slanted copy of the font the system draws them in,
    /// leaning about as far as the system font's own italic. (TextKit 2 ignores `.obliqueness`.)
    private func slantTextWithoutItalics(in range: NSRange) {
        slantTextWithoutItalics(in: range, of: storage)
    }

    private func slantTextWithoutItalics(in range: NSRange, of text: NSMutableAttributedString) {
        (text.string as NSString).enumerateSubstrings(in: range, options: .byComposedCharacterSequences) { character, characterRange, _, _ in
            guard let character, let scalar = character.unicodeScalars.first, EditorTheme.lacksItalics(scalar),
                  let base = text.attribute(.font, at: characterRange.location, effectiveRange: nil) as? PlatformFont else { return }
            text.addAttribute(.font, value: self.obliqueFont(for: character, base: base), range: characterRange)
        }
    }

    /// A page ready to show: block, inline and display attributes, numbers and places in runs of
    /// code or quote lines, all set as the text is put together. Styling a long page line by line
    /// once it was in the text view took a tenth of a second. The parser has already sorted out
    /// list levels.
    func styledText(for document: BiteDocument) -> NSMutableAttributedString {
        let blocks = document.blocks.isEmpty ? [Block()] : document.blocks
        let numbers = ListNumbering.numbers(for: blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        let text = NSMutableAttributedString()
        var italicRanges: [NSRange] = []
        for (index, block) in blocks.enumerated() {
            var position = RunPosition.single
            if block.kind == .code || block.kind == .quote {
                let previousIsSame = index > 0 && blocks[index - 1].kind == block.kind
                let nextIsSame = index + 1 < blocks.count && blocks[index + 1].kind == block.kind
                position = switch (previousIsSame, nextIsSame) {
                case (false, false): .single
                case (false, true): .first
                case (true, true): .middle
                case (true, false): .last
                }
            }
            let attributes = BlockAttributes(block)
            var lineAttributes = attributes.dictionary
            lineAttributes[.biteOrdinal] = numbers[index]?.ordinal ?? 0
            lineAttributes[.biteShownStyle] = numbers[index]?.style?.rawValue ?? ""
            lineAttributes[.biteRunPosition] = position.rawValue
            for run in block.runs {
                let inline = block.kind == .code ? [] : run.style
                var runAttributes = lineAttributes
                runAttributes[.biteInline] = inline.rawValue
                runAttributes.merge(displayAttributes(for: attributes, inline: inline, runPosition: position)) { $1 }
                if block.kind != .code, let link = run.link {
                    runAttributes[.biteLink] = link
                    if !link.isEmpty { runAttributes.merge(theme.linkAttributes(for: attributes)) { $1 } }
                }
                if inline.contains(.italic) {
                    italicRanges.append(NSRange(location: text.length, length: (run.text as NSString).length))
                }
                text.append(NSAttributedString(string: run.text, attributes: runAttributes))
            }
            lineAttributes[.biteInline] = 0
            lineAttributes.merge(displayAttributes(for: attributes, inline: [], runPosition: position)) { $1 }
            text.append(NSAttributedString(string: "\n", attributes: lineAttributes))
        }
        for range in italicRanges {
            slantTextWithoutItalics(in: range, of: text)
        }
        markWrittenLinks(in: text, blocks: blocks)
        return text
    }

    /// As `markWrittenLinks(inLine:as:)` does, for a page being put together.
    private func markWrittenLinks(in text: NSMutableAttributedString, blocks: [Block]) {
        let string = text.string as NSString
        var location = 0
        for block in blocks {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(line)
            guard block.kind != .code else { continue }
            for range in writtenLinks(inLine: line, of: text) {
                text.addAttribute(.biteWrittenLink, value: string.substring(with: range), range: range)
                text.addAttributes(theme.linkAttributes(for: BlockAttributes(block)), range: range)
            }
        }
    }

    private var obliqueFonts: [String: PlatformFont] = [:]

    private func obliqueFont(for character: String, base: PlatformFont) -> PlatformFont {
        let fallback = CTFontCreateForString(base as CTFont, character as CFString, CFRange(location: 0, length: (character as NSString).length))
        let key = "\(CTFontCopyPostScriptName(fallback)) \(CTFontGetSize(fallback))"
        if let font = obliqueFonts[key] { return font }
        var slant = CGAffineTransform(a: 1, b: 0, c: EditorTheme.italicSlant, d: 1, tx: 0, ty: 0)
        let font = CTFontCreateCopyWithAttributes(fallback, CTFontGetSize(fallback), &slant, nil) as PlatformFont
        obliqueFonts[key] = font
        return font
    }

    /// The lines whose list level, number or place among code or quote lines an edit of `range`
    /// can have changed (every line when it's nil), and one more on either side, since those
    /// depend on their neighbours. A list line's number and level depend on the items above it
    /// in its list, so its whole list is included, and so is the list after the edit, which may
    /// have been joined to it or split off. A line that isn't a list starts numbering and
    /// nesting over, so nothing past one can have changed.
    private struct Region {
        var lines: [(range: NSRange, block: BlockAttributes)]
        /// Where the lines whose numbers and levels are worked out start: at the page's first
        /// line or at one that isn't a list.
        var listsFrom: Int
        var kindBefore: BlockKind?
        var kindAfter: BlockKind?
    }

    private func region(around range: NSRange?) -> Region {
        guard let range, storage.length > 0 else { return Region(lines: allLines(), listsFrom: 0) }
        let first = lineRange(at: range.location)
        let last = lineRange(at: max(range.location, NSMaxRange(range) - 1))
        var listStart = first
        while listStart.location > 0, block(of: listStart).kind.isList {
            listStart = lineRange(at: listStart.location - 1)
        }
        var end = last
        while NSMaxRange(end) < storage.length {
            end = lineRange(at: NSMaxRange(end))
            if !block(of: end).kind.isList { break }
        }
        let start = listStart.location == first.location && first.location > 0 ? lineRange(at: first.location - 1) : listStart
        var lines: [(range: NSRange, block: BlockAttributes)] = []
        var position = start.location
        while position < NSMaxRange(end) {
            let line = lineRange(at: position)
            lines.append((line, block(of: line)))
            position = NSMaxRange(line)
        }
        return Region(lines: lines, listsFrom: start.location == listStart.location ? 0 : 1,
                      kindBefore: start.location > 0 ? block(of: lineRange(at: start.location - 1)).kind : nil,
                      kindAfter: NSMaxRange(end) < storage.length ? block(of: lineRange(at: NSMaxRange(end))).kind : nil)
    }

    private func updateStructure(around range: NSRange?) {
        var region = region(around: range)
        normalizeListIndents(&region)
        updateDerivedAttributes(region)
    }

    /// Markdown can't say that a list item sits more than one level below the item above it, or
    /// that a list starts indented, so the file would read back flatter than the page looked.
    /// That comes up when a parent line is deleted, outdented or turned into text: its children
    /// are pulled up here (see `ListNesting`), in the same undo step as the edit. Undo and redo
    /// replay states that were already sorted out, one piece at a time, so they're left alone.
    private func normalizeListIndents(_ region: inout Region) {
        if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing { return }
        let lines = region.lines[region.listsFrom...]
        let levels = ListNesting.levels(for: lines.map { ($0.block.kind, $0.block.indent) })
        let changed = zip(lines.indices, levels).filter { region.lines[$0].block.indent != $1 }
        guard let first = changed.first?.0, let last = changed.last?.0 else { return }
        let range = NSRange(location: region.lines[first].range.location,
                            length: NSMaxRange(region.lines[last].range) - region.lines[first].range.location)
        let previous = storage.attributedSubstring(from: range)
        let selection = textView.selectedRange
        textView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                guard controller.textIsStill(previous.string, at: range) else { return }
                controller.replace(range, with: previous, selection: selection)
            }
        }
        storage.beginEditing()
        for (index, level) in changed {
            storage.addAttribute(.biteIndent, value: level, range: region.lines[index].range)
            region.lines[index].block.indent = level
            restyleLine(region.lines[index].range)
        }
        storage.endEditing()
    }

    /// Numbers for ordered lists, and each code or quote line's place among its neighbours.
    private func updateDerivedAttributes(_ region: Region) {
        let lines = region.lines
        let numbers = ListNumbering.numbers(for: lines[region.listsFrom...].map {
            ($0.block.kind, $0.block.indent, $0.block.number, $0.block.numberStyle)
        })
        storage.beginEditing()
        for (index, line) in lines.enumerated() {
            if index >= region.listsFrom {
                let number = numbers[index - region.listsFrom]
                setLineAttribute(.biteOrdinal, number?.ordinal ?? 0, on: line.range)
                setLineAttribute(.biteShownStyle, number?.style?.rawValue ?? "", on: line.range)
            }
            var position = RunPosition.single
            let kind = line.block.kind
            if kind == .code || kind == .quote {
                let previousIsSame = (index > 0 ? lines[index - 1].block.kind : region.kindBefore) == kind
                let nextIsSame = (index + 1 < lines.count ? lines[index + 1].block.kind : region.kindAfter) == kind
                position = switch (previousIsSame, nextIsSame) {
                case (false, false): .single
                case (false, true): .first
                case (true, true): .middle
                case (true, false): .last
                }
            }
            if setLineAttribute(.biteRunPosition, position.rawValue, on: line.range), line.block.kind == .code {
                restyleLine(line.range)
            }
        }
        storage.endEditing()
    }

    /// Sets a derived attribute on the whole of a line, unless it has it all along already. A
    /// line joined from two can carry two values: the first line's, and on its new line break
    /// the second line's, which typing then spread over the line (the number of an item joined
    /// with the empty line below it turned to 0). Returns whether anything changed.
    @discardableResult
    private func setLineAttribute<Value: Equatable>(_ key: NSAttributedString.Key, _ value: Value, on line: NSRange) -> Bool {
        var range = NSRange()
        let current = storage.attribute(key, at: line.location, longestEffectiveRange: &range, in: line) as? Value
        guard current != value || range != line else { return false }
        storage.addAttribute(key, value: value, range: line)
        return true
    }

    private func updateTypingAttributes() {
        guard storage.length > 0, !textView.isComposing else { return }
        let selection = clamp(textView.selectedRange)
        let block = block(of: lineRange(at: selection.location))
        let inline = typingStyle(at: selection.location)
        textView.typingAttributes = typingAttributes(atLineOf: selection.location, inline: inline,
                                                     link: linkContinued(by: NSRange(location: selection.location, length: 0)))
        textView.isTypingCode = block.kind == .code || inline.contains(.code)
        #if canImport(UIKit)
        if FormatBar.shared.editor === self {
            FormatBar.shared.refresh()
        }
        #endif
    }

    /// Everything text typed into the line at `location` gets: the line's own and derived
    /// attributes, `inline`, the link it's part of, and what they look like.
    private func typingAttributes(atLineOf location: Int, inline: InlineStyle, link: String? = nil) -> [NSAttributedString.Key: Any] {
        guard storage.length > 0 else { return [:] }
        let lineAttributes = storage.attributes(at: lineRange(at: location).location, effectiveRange: nil)
        let block = BlockAttributes(lineAttributes)
        let inline = block.kind == .code ? [] : inline
        let runPosition = RunPosition(rawValue: lineAttributes[.biteRunPosition] as? Int ?? 0) ?? .single
        var typing = block.dictionary
        typing[.biteInline] = inline.rawValue
        typing[.biteOrdinal] = lineAttributes[.biteOrdinal] ?? 0
        typing[.biteShownStyle] = lineAttributes[.biteShownStyle] ?? ""
        typing[.biteRunPosition] = runPosition.rawValue
        typing.merge(displayAttributes(for: block, inline: inline, runPosition: runPosition)) { $1 }
        if let link, block.kind != .code {
            typing[.biteLink] = link
            if !link.isEmpty { typing.merge(theme.linkAttributes(for: block)) { $1 } }
        }
        return typing
    }

    /// The link text typed at `range` is part of: one the caret is inside, not at either end of,
    /// or one all the replaced text is in. Typing on at the end of a link, as after pasting it,
    /// is no longer the link.
    private func linkContinued(by range: NSRange) -> String? {
        guard storage.length > 1, block(of: lineRange(at: range.location)).kind != .code else { return nil }
        let link = { (location: Int) -> String? in
            location >= 0 && location < self.storage.length ? self.storage.attribute(.biteLink, at: location, effectiveRange: nil) as? String : nil
        }
        guard range.length > 0 else {
            guard let before = link(range.location - 1), link(range.location) == before else { return nil }
            return before
        }
        var effective = NSRange()
        guard let first = storage.attribute(.biteLink, at: range.location, longestEffectiveRange: &effective, in: range) as? String,
              NSMaxRange(effective) >= NSMaxRange(range) else { return nil }
        return first
    }

    #if DEBUG
    /// The page as Markdown, without the final newline. For tests.
    var markdownForTesting: String {
        var markdown = MarkdownSerializer.markdown(from: AttributedDocument.document(from: storage))
        if markdown.hasSuffix("\n") { markdown.removeLast() }
        return markdown
    }
    #endif

    // MARK: Helpers

    /// A divider holds no text, so the caret doesn't stop on one, where typing would have turned
    /// it into text: it goes on past it, to the start of the next line with text, or, coming up
    /// from the line below, to the end of the line above. Backspace on the next line deletes the
    /// divider. One at the very end keeps the caret, so backspace can still take it away.
    ///
    /// Dividers in a row are passed over all at once. One at a time, the caret coming up from
    /// below two of them went back and forth between them without end, and the app crashed.
    private func stepOverDivider(_ selection: NSRange) -> NSRange {
        guard selection.length == 0 else { return selection }
        let line = lineRange(at: selection.location)
        guard block(of: line).kind == .divider, NSMaxRange(line) < storage.length else { return selection }
        // The first line after the dividers (the last one, if they run to the end), and the last
        // line before them (the first one, if they start the page).
        var below = lineRange(at: NSMaxRange(line))
        while block(of: below).kind == .divider, NSMaxRange(below) < storage.length {
            below = lineRange(at: NSMaxRange(below))
        }
        var above = line
        while block(of: above).kind == .divider, above.location > 0 {
            above = lineRange(at: above.location - 1)
        }
        // Coming up from below goes above them, if there's text there. Otherwise the caret goes
        // below them: to the next line with text, or to the last divider on the page.
        if NSLocationInRange(lastCaretLocation, below), block(of: above).kind != .divider {
            return NSRange(location: NSMaxRange(above) - 1, length: 0)
        }
        return NSRange(location: below.location, length: 0)
    }

    /// Keeps the selection off the final newline.
    private func clamp(_ selection: NSRange) -> NSRange {
        let end = max(0, storage.length - 1)
        let location = min(selection.location, end)
        return NSRange(location: location, length: max(0, min(NSMaxRange(selection), end) - location))
    }

    private func allLines() -> [(range: NSRange, block: BlockAttributes)] {
        var lines: [(range: NSRange, block: BlockAttributes)] = []
        var position = 0
        while position < storage.length {
            let line = lineRange(at: position)
            lines.append((line, block(of: line)))
            position = NSMaxRange(line)
        }
        return lines
    }

    private func lineRange(at location: Int) -> NSRange {
        string.paragraphRange(for: NSRange(location: min(location, max(0, storage.length - 1)), length: 0))
    }

    private func contentRange(of line: NSRange) -> Range<Int> {
        AttributedDocument.contentRange(of: line, in: string)
    }

    private func block(of line: NSRange) -> BlockAttributes {
        guard line.location < storage.length else { return BlockAttributes() }
        return BlockAttributes(storage.attributes(at: line.location, effectiveRange: nil))
    }

    private func inlineStyle(at location: Int) -> InlineStyle {
        InlineStyle(rawValue: storage.attribute(.biteInline, at: location, effectiveRange: nil) as? Int ?? 0)
    }

    /// The style text typed at `location` gets: that of the text before it on its line, unless a
    /// format button or a shortcut has just set it. Code has none.
    private func typingStyle(at location: Int) -> InlineStyle {
        let line = lineRange(at: location)
        guard block(of: line).kind != .code else { return [] }
        if let override = typingOverride, override.location == location { return override.style }
        return location > line.location ? inlineStyle(at: location - 1) : []
    }

    /// The styles of the text in `range`, leaving out line breaks and code, which have none.
    private func inlineStyles(in range: NSRange) -> [InlineStyle] {
        var styles: [InlineStyle] = []
        var position = range.location
        while position < NSMaxRange(range) {
            let line = lineRange(at: position)
            position = NSMaxRange(line)
            guard block(of: line).kind != .code else { continue }
            let content = contentRange(of: line)
            let text = NSIntersectionRange(range, NSRange(location: content.lowerBound, length: content.count))
            if text.length > 0 {
                styles += inlineRuns(in: storage, range: text).map(\.style)
            }
        }
        return styles
    }

    private func inlineRuns(in text: NSAttributedString, range: NSRange? = nil) -> [(range: NSRange, style: InlineStyle)] {
        var runs: [(range: NSRange, style: InlineStyle)] = []
        text.enumerateAttribute(.biteInline, in: range ?? NSRange(location: 0, length: text.length)) { value, runRange, _ in
            runs.append((runRange, InlineStyle(rawValue: value as? Int ?? 0)))
        }
        return runs
    }

    private func lineBreakAttributes(for block: BlockAttributes) -> [NSAttributedString.Key: Any] {
        var attributes = block.dictionary
        attributes[.biteInline] = 0
        return attributes
    }

    private func selectedLines() -> [NSRange] {
        let covered = string.paragraphRange(for: clamp(textView.selectedRange))
        var lines: [NSRange] = []
        var position = covered.location
        while position < NSMaxRange(covered) {
            let line = lineRange(at: position)
            lines.append(line)
            position = NSMaxRange(line)
        }
        return lines
    }
}
