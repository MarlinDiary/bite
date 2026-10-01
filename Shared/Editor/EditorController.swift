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
            textView.typingAttributes = typingAttributes(atLineOf: edit.location, inline: edit.inline)
            return
        }
        let block = block(of: lineRange(at: range.location))
        // Typing over text carries on in the style of that text.
        let inline = range.length > 0 && block.kind != .code ? inlineStyle(at: range.location) : typingStyle(at: range.location)
        let joinsLines = range.length > 0 && string.substring(with: range).contains("\n")
        pendingEdit = PendingEdit(location: range.location, lengthBefore: storage.length, replacedLength: range.length,
                                  block: block, inline: inline, joinsLines: joinsLines)
        // The text goes in with the attributes it's due, not only stamped with them afterwards
        // (`apply`): UIKit's undo and redo bring it back as it went in. Text being composed in
        // an input method went in with none when UIKit had reset the typing attributes, and
        // undoing it passed through a state where it started the line, so the line lost its kind.
        textView.typingAttributes = typingAttributes(atLineOf: range.location, inline: inline)
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
    private static let shortcutTriggers = InputRules.inlineMarkers.union([" ", "\u{3000}", "-", "`", "\u{00B7}"])

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
        guard InputRules.inlineMarkers.contains(character) else { return false }
        // Code stands in as characters that are neither spaces, letters nor markers, the way
        // its backticks sit in Markdown. Same length, so the match's offsets still hold.
        let text = NSMutableString(string: prefix)
        for range in code {
            text.replaceCharacters(in: range, with: String(repeating: "#", count: range.length))
        }
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

    func toggleTodo(at location: Int) {
        finishComposing()
        let line = lineRange(at: location)
        guard block(of: line).kind == .todo else { return }
        setBlocks(of: [line]) { $0.isChecked.toggle() }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
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
        let inserted = NSAttributedString(string: isCode ? runs.map(\.text).joined() : text, attributes: attributes)
        replace(selection, with: inserted, selection: NSRange(location: selection.location + inserted.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange)
        return true
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

    /// Replaces `range` and registers the inverse with the text view's undo manager. `undo`
    /// overrides what undo restores; by default it's the text that was there.
    private func replace(_ range: NSRange, with replacement: NSAttributedString, selection: NSRange,
                         undo: (text: NSAttributedString, selection: NSRange)? = nil) {
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
        textView.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                guard controller.textIsStill(textAfter, at: linesAfter) else { return }
                controller.replace(linesAfter, with: previous, selection: previousSelection)
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
        contentDidChange(in: replacedRange)
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

    private func setBlocks(of lines: [NSRange], _ change: (inout BlockAttributes) -> Void) {
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
        replace(range, with: replacement, selection: textView.selectedRange)
    }

    /// `withinLine` is for typing that stays inside one line. That can't change any line's kind,
    /// level or number, so those aren't worked out again, which took longer than a frame on
    /// every keystroke in a long page.
    private func contentDidChange(in range: NSRange, withinLine: Bool = false) {
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
        if textView.isFirstResponder {
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
    func textViewWritingToolsDidEnd(_ textView: UITextView) {
        settleUnannouncedEdit()
    }
    #else
    func textViewWritingToolsDidEnd(_ textView: NSTextView) {
        settleUnannouncedEdit()
    }

    @objc private func undoManagerDidChange(_ notification: Notification) {
        settleUnannouncedEdit()
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
        }
        // A line break holds no text, so it never takes an inline style, whatever came with it:
        // text typed or pasted across lines, a style set over lines. Styled, it drew a
        // strikethrough past the end of the line, and an empty line left behind in bold or
        // italic kept the wrong font.
        if let lastCharacter = line.length > 0 ? NSMaxRange(line) - 1 : nil, string.character(at: lastCharacter) == 0x0A {
            storage.addAttribute(.biteInline, value: 0, range: NSRange(location: lastCharacter, length: 1))
        }
        styleText(in: line, as: block)
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
        storage.endEditing()
    }

    /// The display attributes of `range`, on a line of kind `block`, from its inline styles.
    private func styleText(in range: NSRange, as block: BlockAttributes) {
        let runPosition = RunPosition(rawValue: storage.attribute(.biteRunPosition, at: range.location, effectiveRange: nil) as? Int ?? 0) ?? .single
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.strikethroughColor, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        for (run, inline) in inlineRuns(in: storage, range: range) {
            storage.addAttributes(displayAttributes(for: block, inline: inline, runPosition: runPosition), range: run)
            if inline.contains(.italic), block.kind != .code {
                slantTextWithoutItalics(in: run)
            }
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
        return text
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
        textView.typingAttributes = typingAttributes(atLineOf: selection.location, inline: inline)
        textView.isTypingCode = block.kind == .code || inline.contains(.code)
        #if canImport(UIKit)
        if FormatBar.shared.editor === self {
            FormatBar.shared.refresh()
        }
        #endif
    }

    /// Everything text typed into the line at `location` gets: the line's own and derived
    /// attributes, `inline`, and what they look like.
    private func typingAttributes(atLineOf location: Int, inline: InlineStyle) -> [NSAttributedString.Key: Any] {
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
        return typing
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
