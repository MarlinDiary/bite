#if !canImport(UIKit)
import AppKit
import Testing
import BiteKit
@testable import Bite

/// What only a Mac has: the menus' commands and keys, which go to the page being edited.
@MainActor
struct MacMenuTests {
    @Test func undoFromTheEditMenuTakesBackThisPagesEdit() {
        let editor = EditorHarness("a")
        let other = EditorHarness("b")
        editor.moveCaret(line: 0)
        editor.type("x")
        other.moveCaret(line: 0)
        other.type("y")
        #expect(editor.textView.tryToPerform(Selector(("undo:")), with: nil))
        #expect(editor.markdown == "a")
        #expect(other.markdown == "by")
    }

    @Test func formatMenuStylesTheSelection() {
        let editor = EditorHarness("a word here")
        editor.select(from: (0, 2), to: (0, 6))
        #expect(editor.textView.tryToPerform(#selector(BiteTextView.toggleBold(_:)), with: nil))
        #expect(editor.markdown == "a **word** here")
        let item = NSMenuItem(title: "Bold", action: #selector(BiteTextView.toggleBold(_:)), keyEquivalent: "b")
        _ = editor.textView.validateMenuItem(item)
        #expect(item.state == .on)
        #expect(editor.textView.tryToPerform(#selector(BiteTextView.toggleInlineCode(_:)), with: nil))
        #expect(editor.markdown == "a **`word`** here")
    }

    @Test func shiftTabOutdents() {
        let editor = EditorHarness("- a\n- b")
        editor.moveCaret(line: 1)
        editor.type("\t")
        #expect(editor.markdown == "- a\n    - b")
        editor.textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(editor.markdown == "- a\n- b")
    }

    /// Option-Return and Shift-Return put no line break inside a line: they're Return.
    @Test func aLineBreakIsReturn() {
        let editor = EditorHarness("- a")
        editor.moveCaret(line: 0)
        editor.textView.doCommand(by: #selector(NSResponder.insertLineBreak(_:)))
        editor.type("b")
        #expect(editor.markdown == "- a\n- b")
        #expect(!editor.textView.text.contains("\u{2028}"))
    }

    @Test func aClickOnTheCheckboxFindsItsLine() throws {
        let editor = EditorHarness("text\n- [ ] task")
        editor.textView.layoutSubtreeIfNeeded()
        let layoutManager = try #require(editor.textView.textLayoutManager)
        var checkbox: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let line = fragment as? BlockLayoutFragment, line.block.kind == .todo {
                checkbox = line.checkboxFrame
                return false
            }
            return true
        }
        let frame = try #require(checkbox)
        let origin = editor.textView.textContainerOrigin
        let point = NSPoint(x: frame.midX + origin.x, y: frame.midY + origin.y)
        #expect(editor.textView.todoLocation(at: point) == 5)
        #expect(editor.textView.todoLocation(at: NSPoint(x: point.x + 80, y: point.y)) == nil)
        // Below the last line, where there's no line at all.
        #expect(editor.textView.todoLocation(at: NSPoint(x: point.x, y: point.y + 300)) == nil)
    }

    @Test func spellingIsntCheckedInCode() {
        let editor = EditorHarness("```\nxcodebuld\n```\nspeling `inlin`")
        let text = editor.textView.text as NSString
        let ranges = ["xcodebuld", "speling", "inlin"].map { text.range(of: $0) }
        let results = ranges.map { NSTextCheckingResult.spellCheckingResult(range: $0) }
        let kept = editor.controller.textView(editor.textView, didCheckTextIn: NSRange(location: 0, length: text.length),
                                              types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: [:],
                                              results: results, orthography: NSOrthography.defaultOrthography(forLanguage: "en"),
                                              wordCount: 3)
        #expect(kept.map(\.range) == [ranges[1]])
    }

    /// AppKit sets the selection over and over while a drag selects, and asks its delegate only at
    /// the end. Past the last line the highlight lit up the empty space, and snapped back once
    /// the mouse let go.
    @Test func aDragNeverSelectsPastTheLastLine() {
        let editor = EditorHarness("first\nlast")
        let length = (editor.textView.text as NSString).length
        editor.textView.setSelectedRange(NSRange(location: 6, length: length - 6), affinity: .downstream, stillSelecting: true)
        #expect(editor.textView.selectedRange == NSRange(location: 6, length: 4))
    }

    /// A click on a divider puts the caret past it at once, not after the mouse lets go.
    @Test func aClickNeverLeavesTheCaretOnADivider() {
        let editor = EditorHarness("above\n---\nbelow")
        editor.moveCaret(line: 0)
        // A divider holds no text: its line is just a line break.
        let below = (editor.textView.text as NSString).range(of: "below").location
        editor.textView.setSelectedRange(NSRange(location: below - 1, length: 0), affinity: .downstream, stillSelecting: true)
        #expect(editor.textView.selectedRange == NSRange(location: below, length: 0))
    }

    /// A shortcut typed in Settings reads as menus write it, and needs a modifier besides Shift.
    @Test func aTypedShortcut() throws {
        func press(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
        }
        let optionCommandB = try #require(press("b", keyCode: 11, [.command, .option]))
        let shortcut = try #require(Shortcut(optionCommandB))
        #expect(shortcut.title == "\u{2325}\u{2318}B")
        #expect(shortcut.keyCode == 11)
        #expect(shortcut.modifiers == UInt32(0x0100 | 0x0800))
        let shiftB = try #require(press("b", keyCode: 11, [.shift]))
        #expect(Shortcut(shiftB) == nil)
        let controlSpace = try #require(press(" ", keyCode: 49, [.control]))
        #expect(Shortcut(controlSpace)?.title == "\u{2303}Space")
    }

    /// Pasted Markdown keeps its lines, as on the phone, from the Edit menu's Paste.
    @Test func pasteFromTheEditMenuReadsMarkdown() {
        let editor = EditorHarness("")
        Clipboard.string = "- one\n- two"
        editor.textView.paste(nil)
        #expect(editor.markdown == "- one\n- two")
    }
}
#endif
