#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// A line opened at the end of a page to type on, as Bite's icon on the Home Screen offers.
@MainActor
struct StartLineTests {
    private func kinds(_ editor: EditorHarness) -> [BlockKind] {
        MarkdownParser.parse(editor.markdown).blocks.map(\.kind)
    }

    @Test func aNewLineGoesBelowTheLastLineWithTheKeyboard() {
        let editor = EditorHarness("First\nSome text")
        editor.endEditing()
        editor.controller.startLine(asToDo: false)
        #expect(editor.textView.isFirstResponder)
        // On the new last line, before the page's closing line break.
        #expect(editor.caret == editor.textView.text.count - 1)
        editor.type("more")
        #expect(editor.markdown == "First\nSome text\nmore")
    }

    @Test func aNewToDoGoesBelowTheLastLine() {
        let editor = EditorHarness("Some text")
        editor.controller.startLine(asToDo: true)
        editor.type("milk")
        #expect(editor.markdown == "Some text\n- [ ] milk")
    }

    /// Whatever the page ends with: a list doesn't carry on, as it would with Return.
    @Test func itsKindIsTheOnePickedWhateverTheLineAbove() {
        let list = EditorHarness("- one\n- two")
        list.controller.startLine(asToDo: false)
        list.type("after")
        #expect(kinds(list) == [.bullet, .bullet, .paragraph])
        let heading = EditorHarness("# Title")
        heading.controller.startLine(asToDo: true)
        heading.type("first")
        #expect(heading.markdown == "# Title\n- [ ] first")
    }

    /// An empty last line is used rather than another put under it, made the kind picked: one
    /// started and left empty is the one used the next time.
    @Test func anEmptyLastLineIsTheOneUsed() {
        let editor = EditorHarness("a")
        editor.controller.startLine(asToDo: true)
        editor.endEditing()
        editor.controller.startLine(asToDo: true)
        #expect(kinds(editor) == [.paragraph, .todo])
        editor.controller.startLine(asToDo: false)
        // The to-do made plain text, which Markdown doesn't show while it's empty.
        #expect(editor.textView.text == "a\n\n")
        editor.type("b")
        #expect(editor.markdown == "a\nb")
        let empty = EditorHarness("")
        empty.controller.startLine(asToDo: true)
        empty.type("x")
        #expect(empty.markdown == "- [ ] x")
    }

    @Test func undoTakesItBack() {
        let editor = EditorHarness("a")
        editor.controller.startLine(asToDo: true)
        editor.undo()
        #expect(editor.markdown == "a")
        let list = EditorHarness("a\n- ")
        list.controller.startLine(asToDo: true)
        #expect(kinds(list) == [.paragraph, .todo])
        list.undo()
        #expect(kinds(list) == [.paragraph, .bullet])
    }
}
