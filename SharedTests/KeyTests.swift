import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import Bite

/// Return: lists carry on, everything else goes back to a plain paragraph, as in Notion.
struct ReturnTests {
    @Test func bulletContinues() {
        let editor = EditorHarness()
        editor.type("- a\nb")
        #expect(editor.markdown == "- a\n- b")
    }

    @Test func emptyBulletEndsTheList() {
        let editor = EditorHarness()
        editor.type("- a\n\nb")
        #expect(editor.markdown == "- a\nb")
    }

    @Test func todoContinuesUnchecked() {
        let editor = EditorHarness()
        editor.type("[x] a\nb")
        #expect(editor.markdown == "- [x] a\n- [ ] b")
    }

    @Test func numberedListCounts() {
        let editor = EditorHarness()
        editor.type("1. a\nb\nc")
        #expect(editor.markdown == "1. a\n2. b\n3. c")
    }

    @Test func quoteContinuesOnReturn() {
        let editor = EditorHarness()
        editor.type("> said\nnext")
        #expect(editor.markdown == "> said\n> next")
    }

    @Test func emptyQuoteLineEndsTheQuote() {
        let editor = EditorHarness()
        editor.type("> said\n\nafter")
        #expect(editor.markdown == "> said\nafter")
    }

    @Test func returnInsideAQuoteSplitsIt() {
        let editor = EditorHarness("> abcd")
        editor.moveCaret(line: 0, column: 2)
        editor.type("\n")
        #expect(editor.markdown == "> ab\n> cd")
    }

    @Test func returnAtStartOfAQuoteOpensAQuoteLineAbove() {
        let editor = EditorHarness("> said")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\n")
        #expect(editor.markdown == ">\n> said")
        #expect(editor.caret == 1)
    }

    @Test func emptyQuoteBecomesParagraph() {
        let editor = EditorHarness()
        editor.type("> \nx")
        #expect(editor.markdown == "x")
    }

    @Test func headingEndsOnReturn() {
        let editor = EditorHarness()
        editor.type("# Title\nbody")
        #expect(editor.markdown == "# Title\nbody")
    }

    @Test func splittingAHeadingLeavesAParagraph() {
        let editor = EditorHarness("# Hello world")
        editor.moveCaret(line: 0, column: 5)
        editor.type("\n")
        #expect(editor.markdown == "# Hello\n world")
        #expect(editor.caret == 6)
    }

    @Test func returnAtStartOfHeadingOpensALineAbove() {
        let editor = EditorHarness("# Title")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\n")
        #expect(editor.markdown == "\n# Title")
        #expect(editor.caret == 1)
    }

    @Test func returnAtStartOfItemOpensAnItemAbove() {
        let editor = EditorHarness("- [x] done")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\n")
        #expect(editor.markdown == "- [ ]\n- [x] done")
        #expect(editor.caret == 1)
    }

    @Test func emptyNestedItemMovesUpALevel() {
        let editor = EditorHarness()
        editor.type("- a\n\tb\n\nc")
        #expect(editor.markdown == "- a\n    - b\n- c")
    }

    @Test func codeContinuesAndABlankLastLineEndsIt() {
        let editor = EditorHarness()
        editor.type("```x\ny\n\nz")
        #expect(editor.markdown == "```\nx\ny\n```\nz")
    }

    @Test func blankLinesInsideCodeStay() {
        let editor = EditorHarness("```\nx\ny\n```")
        editor.moveCaret(line: 0)
        editor.type("\n\n")
        #expect(editor.markdown == "```\nx\n\n\ny\n```")
    }

    @Test func threeBackticksCloseCode() {
        let editor = EditorHarness()
        editor.type("```x\n```after")
        #expect(editor.markdown == "```\nx\n```\nafter")
    }

    @Test func returnOnADividerOpensAParagraphBelow() {
        let editor = EditorHarness("---")
        editor.type("\nx")
        #expect(editor.markdown == "---\nx")
    }
}

struct BackspaceTests {
    @Test func atStartOfBulletMakesAParagraph() {
        let editor = EditorHarness("- a")
        editor.moveCaret(line: 0, column: 0)
        editor.backspace()
        #expect(editor.markdown == "a")
    }

    @Test func atStartOfNestedItemMovesItUp() {
        let editor = EditorHarness("- a\n    - b")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "- a\n- b")
    }

    @Test func atStartOfParagraphJoinsTheLineAbove() {
        let editor = EditorHarness("- a\nb")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "- ab")
    }

    @Test func atStartOfHeadingMakesAParagraph() {
        let editor = EditorHarness("# Title")
        editor.moveCaret(line: 0, column: 0)
        editor.backspace()
        #expect(editor.markdown == "Title")
    }

    @Test func rightAfterAShortcut() {
        let editor = EditorHarness()
        editor.type("- ")
        editor.backspace()
        editor.type("x")
        #expect(editor.markdown == "x")
    }

    @Test func clearingEverythingLeavesAPlainPage() {
        let editor = EditorHarness("- [ ] a\n- [ ] b")
        editor.selectAll()
        editor.backspace()
        #expect(editor.markdown == "")
        editor.type("x")
        #expect(editor.markdown == "x")
    }

    @Test func deletingWholeLinesLeavesTheNextLineAlone() {
        let editor = EditorHarness("- a\n# b\n> c\n1. d")
        editor.select(from: (1, 0), to: (3, 0))
        editor.backspace()
        #expect(editor.markdown == "- a\n1. d")
        editor.undo()
        #expect(editor.markdown == "- a\n# b\n> c\n1. d")
    }

    @Test func backspaceIntoAnEmptyLineTakesItsKind() {
        let editor = EditorHarness("- [ ] \ntext")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "- [ ] text")
    }

    @Test func deletingAcrossLinesKeepsTheFirstLinesKind() {
        let editor = EditorHarness("# Title\nbody text")
        editor.select(from: (0, 2), to: (1, 4))
        editor.backspace()
        #expect(editor.markdown == "# Ti text")
    }
}

/// Typed text belongs to the line it's typed into, whatever UIKit's typing attributes say.
struct TypingIntoLinesTests {
    @Test(arguments: [("1. ", "1. abc"), ("[] ", "- [ ] abc"), ("> ", "> abc"), ("# ", "# abc"), ("- ", "- abc")])
    func emptyLineKeepsItsKindAfterLeavingAndComingBack(marker: String, expected: String) {
        let editor = EditorHarness()
        editor.type("Top\n" + marker)
        editor.moveCaret(line: 0)
        editor.moveCaret(line: 1, column: 0)
        editor.type("abc")
        #expect(editor.markdown == "Top\n" + expected)
    }

    @Test func startOfAnItemBelowAHeading() {
        let editor = EditorHarness("# H\n- item")
        editor.moveCaret(line: 1, column: 0)
        editor.type("x")
        #expect(editor.markdown == "# H\n- xitem")
    }

    @Test func autocorrectKeepsTheLine() {
        let editor = EditorHarness("- teh")
        editor.replace(line: 0, columns: 0..<3, with: "the")
        #expect(editor.markdown == "- the")
    }

    @Test func autocorrectKeepsBold() {
        let editor = EditorHarness("a **teh** b")
        editor.replace(line: 0, columns: 2..<5, with: "the")
        #expect(editor.markdown == "a **the** b")
    }
}

struct UndoTests {
    @Test func undoingABlockShortcutGivesBackWhatWasTyped() {
        let editor = EditorHarness()
        editor.type("- ", separateEvents: true)
        editor.undo()
        #expect(editor.markdown == "\\- ")
        #expect(editor.caret == 2)
    }

    @Test func undoingAnInlineShortcutGivesBackWhatWasTyped() {
        let editor = EditorHarness()
        editor.type("**b**", separateEvents: true)
        editor.undo()
        #expect(editor.markdown == "\\*\\*b\\*\\*")
        #expect(editor.caret == 5)
    }

    @Test func undoingADeletionBringsBackItsStyle() {
        let editor = EditorHarness("a **bold** c")
        editor.select(from: (0, 2), to: (0, 6))
        editor.backspace()
        editor.undo()
        #expect(editor.markdown == "a **bold** c")
    }

    @Test func undoingAJoinBringsBackEachLinesKind() {
        let editor = EditorHarness("- [x] a\n- [ ] b\n1. c\nd")
        editor.select(from: (0, 1), to: (2, 0))
        editor.backspace()
        #expect(editor.markdown == "- [x] ac\nd")
        editor.undo()
        #expect(editor.markdown == "- [x] a\n- [ ] b\n1. c\nd")
        editor.redo()
        #expect(editor.markdown == "- [x] ac\nd")
    }

    @Test func undoingTypingOverLinesBringsThemBack() {
        let editor = EditorHarness("# a\n> b\n- c")
        editor.select(from: (0, 1), to: (2, 0))
        editor.type("x")
        #expect(editor.markdown == "# axc")
        editor.undo()
        #expect(editor.markdown == "# a\n> b\n- c")
    }

    @Test func undoingAPasteOverLinesBringsThemBack() {
        let editor = EditorHarness("# a\n> b\n- c")
        editor.select(from: (0, 1), to: (2, 0))
        editor.controller.paste("p\nq")
        #expect(editor.markdown == "# ap\nqc")
        editor.undo()
        #expect(editor.markdown == "# a\n> b\n- c")
    }
}

struct CommandTests {
    @Test func tappingACheckbox() {
        let editor = EditorHarness("- [ ] a")
        editor.controller.toggleTodo(at: 0)
        #expect(editor.markdown == "- [x] a")
        editor.controller.toggleTodo(at: 0)
        #expect(editor.markdown == "- [ ] a")
    }

    /// A box ticked away from the caret leaves the page where it is, and so does undoing it: the
    /// caret doesn't move, and bringing it into view took the page off the box (user,
    /// 2026-10-05, on the Mac).
    @Test func tickingABoxLeavesThePageWhereItIs() async {
        let editor = EditorHarness("- [ ] box\n" + (1...80).map { "Line \($0)" }.joined(separator: "\n"))
        editor.textView.selectedRange = NSRange(location: editor.storage.length - 1, length: 0)
        await settle(editor)
        scrollToTop(editor)
        let top = scrolled(editor)
        editor.controller.toggleTodo(at: 0)
        await settle(editor)
        #expect(editor.markdown.hasPrefix("- [x] box"))
        #expect(scrolled(editor) == top)
        editor.undo()
        await settle(editor)
        #expect(editor.markdown.hasPrefix("- [ ] box"))
        #expect(scrolled(editor) == top)
    }

    private func scrolled(_ editor: EditorHarness) -> CGFloat {
        #if canImport(UIKit)
        editor.textView.contentOffset.y
        #else
        editor.textView.enclosingScrollView?.contentView.bounds.minY ?? 0
        #endif
    }

    private func scrollToTop(_ editor: EditorHarness) {
        #if canImport(UIKit)
        editor.textView.setContentOffset(CGPoint(x: 0, y: -editor.textView.adjustedContentInset.top), animated: false)
        #else
        editor.textView.scroll(.zero)
        #endif
    }

    /// Lets a caret scroll asked for meanwhile happen.
    private func settle(_ editor: EditorHarness) async {
        #if canImport(UIKit)
        editor.textView.setNeedsLayout()
        editor.textView.layoutIfNeeded()
        #endif
        try? await Task.sleep(for: .milliseconds(50))
        #if canImport(UIKit)
        editor.textView.layoutIfNeeded()
        #endif
    }

    @Test func pastingMarkdown() {
        let editor = EditorHarness()
        editor.controller.paste("- a\n- [ ] b\n**c**")
        #expect(editor.markdown == "- a\n- [ ] b\n**c**")
    }

    @Test func pastingPlainTextIntoAnItem() {
        let editor = EditorHarness("-")
        editor.controller.paste("hello")
        #expect(editor.markdown == "- hello")
    }

    @Test func todoButtonToggles() {
        let editor = EditorHarness("task")
        editor.controller.perform(.todo)
        #expect(editor.markdown == "- [ ] task")
        editor.controller.perform(.todo)
        #expect(editor.markdown == "task")
    }

    @Test func headingButtonCycles() {
        let editor = EditorHarness("t")
        var seen: [String] = []
        for _ in 0..<4 {
            editor.controller.perform(.heading)
            seen.append(editor.markdown)
        }
        #expect(seen == ["# t", "## t", "### t", "t"])
    }

    @Test func headingButtonTakesADeepHeadingBackToText() {
        let editor = EditorHarness("##### t")
        editor.controller.perform(.heading)
        #expect(editor.markdown == "t")
    }
}

/// Input methods such as pinyin compose marked text first, then settle on a candidate that is
/// often shorter than what was spelled.
struct InputMethodTests {
    @Test func composedTextStaysOnItsLine() {
        let editor = EditorHarness("1. one\n2. two\n3. three")
        editor.moveCaret(line: 1)
        editor.type("\n", separateEvents: true)
        editor.controller.perform(.indent)
        editor.compose(["n", "ni", "nih", "niha", "nihao"], commit: "hi")
        #expect(editor.markdown == "1. one\n2. two\n    1. hi\n3. three")
    }

    @Test func composedTextTakesItsLinesStyle() {
        let editor = EditorHarness("- [ ] one\n- [ ] two")
        editor.moveCaret(line: 0)
        editor.compose(["x", "xy", "xyz"], commit: "!")
        #expect(editor.markdown == "- [ ] one!\n- [ ] two")
    }
}
