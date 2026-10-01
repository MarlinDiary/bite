import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import BiteKit
@testable import Bite

/// Typing a line gives what pasting it as Markdown gives: the shortcuts read the line the way
/// the Markdown parser does. Found in a review on 2026-10-01.
@MainActor
struct TypingAsMarkdownTests {
    private func runs(_ editor: EditorHarness) -> [InlineRun] {
        AttributedDocument.document(from: editor.storage).blocks.first?.runs ?? []
    }

    // MARK: Inline code holds no emphasis

    @Test func starsTypedInOpenCodeStayInIt() {
        let editor = EditorHarness()
        editor.type("`**x**`")
        #expect(editor.textView.text == "**x**\n")
        #expect(editor.markdown == "`**x**`")
    }

    @Test func pythonPowersAndGlobsStayCode() {
        let editor = EditorHarness()
        editor.type("`2**3 + 4**5` and `src/**/*.swift`")
        #expect(editor.markdown == "`2**3 + 4**5` and `src/**/*.swift`")
    }

    @Test func typingInsideInlineCodeIsLiteral() {
        let editor = EditorHarness("`ab`")
        editor.moveCaret(line: 0, column: 1)
        editor.type("**x** _y_ ~~z~~")
        #expect(editor.textView.text == "a**x** _y_ ~~z~~b\n")
        #expect(editor.markdown == "`a**x** _y_ ~~z~~b`")
    }

    /// The stars in the code aren't an opening pair for the ones typed after it.
    @Test func aMarkerInCodeEarlierOnTheLineOpensNothing() {
        let editor = EditorHarness("`a**`b")
        editor.moveCaret(line: 0)
        editor.type("**")
        #expect(editor.markdown == "`a**`b\\*\\*")
    }

    /// `-` typed as code, then a space, used to make the line a bullet and take the code away.
    @Test func codeAtTheStartOfALineStartsNoBlock() {
        let editor = EditorHarness()
        editor.type("`-` x")
        #expect(editor.markdown == "`-` x")
    }

    @Test func emphasisStillWrapsCode() {
        let editor = EditorHarness()
        editor.type("**a `b` c**")
        #expect(editor.markdown == "**a `b` c**")
    }

    @Test func emphasisAfterClosedCodeStillWorks() {
        let editor = EditorHarness()
        editor.type("`a` **b**")
        #expect(editor.markdown == "`a` **b**")
    }

    @Test func pastedMarkdownGoesIntoCodeAsText() {
        let editor = EditorHarness("`ab`")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("**x** - y")
        #expect(editor.markdown == "`a**x** - yb`")
    }

    @Test func codeCopiedFromBiteGoesIntoCodeWithoutItsBackticks() {
        let editor = EditorHarness("`ab`")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("`x`")
        #expect(editor.markdown == "`axb`")
    }

    @Test func undoAndRedoOfTypingInCode() {
        let editor = EditorHarness()
        editor.type("`**x**`", separateEvents: true)
        while editor.textView.undoManager?.canUndo == true { editor.undo() }
        #expect(editor.markdown == "")
        while editor.textView.undoManager?.canRedo == true { editor.redo() }
        #expect(editor.markdown == "`**x**`")
    }

    // MARK: Backslashes

    @Test func anEscapedStarOpensNothing() {
        let editor = EditorHarness()
        editor.type("\\*literal*")
        #expect(editor.textView.text == "\\*literal*\n")
        #expect(runs(editor).allSatisfy { $0.style.isEmpty })
    }

    @Test func escapesWorkForEveryMarker() {
        for typed in ["\\**literal**", "\\~~literal~~", "\\_literal_", "*literal\\*", "\\`literal`"] {
            let editor = EditorHarness()
            editor.type(typed)
            #expect(editor.textView.text == typed + "\n", "\(typed)")
        }
    }

    @Test func anEscapedBackslashEscapesNothing() {
        let editor = EditorHarness()
        editor.type("\\\\*x*")
        #expect(runs(editor).map(\.style) == [[], .italic])
    }

    // MARK: Whole characters

    @Test func underscoresInsideWordsOfAnyScript() {
        for word in ["\u{1D49C}_x_", "\u{20BB7}_x_", "e\u{0301}_x_", "snake_case_name"] {
            let editor = EditorHarness()
            editor.type(word)
            #expect(editor.textView.text == word + "\n", "\(word)")
        }
    }

    @Test func anUnderscoreBeforeALetterClosesNothing() {
        let editor = EditorHarness("_xy")
        editor.moveCaret(line: 0, column: 2)
        editor.type("_")
        #expect(editor.textView.text == "_x_y\n")
    }

    @Test func unicodeSpacesAreSpaces() {
        for typed in ["*\u{2003}x*", "*x\u{2003}*", "**\u{2009}x**", "~~\u{00A0}x~~"] {
            let editor = EditorHarness()
            editor.type(typed)
            #expect(editor.textView.text == typed + "\n", "\(typed.debugDescription)")
        }
    }

    // MARK: Saving

    @Test func aListPastNineDigitsReadsBack() {
        let editor = EditorHarness()
        editor.type("999999999. a\nb\nc")
        let saved = editor.markdown
        editor.controller.load(markdown: saved)
        let document = AttributedDocument.document(from: editor.storage)
        #expect(document.blocks.map(\.kind) == [.ordered, .ordered, .ordered])
        #expect(editor.textView.text == "a\nb\nc\n")
        #expect(editor.markdown == saved)
    }

    @Test func aTaskWithATabIsATask() {
        let editor = EditorHarness()
        editor.controller.paste("- [x]\titem")
        let block = AttributedDocument.document(from: editor.storage).blocks.first
        #expect(block?.kind == .todo)
        #expect(block?.isChecked == true)
        #expect(editor.markdown == "- [x] item")
    }

    // MARK: Typing and pasting agree

    /// Each of these comes out the same typed one key at a time as pasted in one go.
    @Test func typedLikePasted() {
        let lines = ["**x**", "*y*", "_z_", "~~s~~", "`c`", "`**x**`", "`a*b*c`", "**a `b` c**", "\u{1D49C}_x_",
                     "\u{20BB7}_x_", "snake_case_name", "*\u{2003}x*", "a*b*c", "**bold** and *it*", "~~a~~ `b`", "x_y_",
                     "- **x**", "1. `c`", "> _q_", "# *h*", "- [ ] ~~done~~"]
        for line in lines {
            let typed = EditorHarness()
            typed.type(line)
            let pasted = EditorHarness()
            pasted.controller.paste(line)
            #expect(typed.markdown == pasted.markdown, "\(line.debugDescription)")
        }
    }
}
