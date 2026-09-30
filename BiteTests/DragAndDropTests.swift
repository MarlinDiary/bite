import Testing
import UIKit
import BiteKit
@testable import Bite

/// Text dragged within a page moves as if cut and pasted where it's dropped. Left to UIKit, the
/// drop went straight into the text storage: the editor never heard of it, so the page wasn't
/// saved, there was no undo, and text dropped at the start of a line turned the line into the
/// kind of line it came from.
@MainActor
struct DragAndDropTests {
    private func location(_ editor: EditorHarness, line: Int, column: Int) -> Int {
        let lines = editor.textView.text.components(separatedBy: "\n")
        return lines[..<line].reduce(0) { $0 + ($1 as NSString).length + 1 } + column
    }

    private func range(_ editor: EditorHarness, line: Int, _ columns: Range<Int>) -> NSRange {
        NSRange(location: location(editor, line: line, column: columns.lowerBound), length: columns.count)
    }

    @Test func textDroppedAtTheStartOfALineJoinsThatLine() {
        let editor = EditorHarness("- apple\n- **banana** split\nplain text here")
        editor.controller.move(range(editor, line: 1, 0..<12), to: location(editor, line: 2, column: 0))
        #expect(editor.markdown == "- apple\n-\n**banana** splitplain text here")
    }

    @Test func textDroppedIntoAListItemStaysInIt() {
        let editor = EditorHarness("- apple\nplain")
        editor.controller.move(range(editor, line: 1, 0..<5), to: location(editor, line: 0, column: 0))
        #expect(editor.markdown == "- plainapple\n")
    }

    @Test func textDroppedMidLineKeepsItsStyle() {
        let editor = EditorHarness("- **banana** split\nplain text here")
        editor.controller.move(range(editor, line: 0, 0..<7), to: location(editor, line: 1, column: 8))
        #expect(editor.markdown == "- split\nplain te**banana** xt here")
    }

    @Test func textDroppedEarlierInItsOwnLine() {
        let editor = EditorHarness("one two three")
        editor.controller.move(range(editor, line: 0, 4..<8), to: location(editor, line: 0, column: 0))
        #expect(editor.markdown == "two one three")
    }

    @Test func wholeLinesMoveAsLines() {
        let editor = EditorHarness("a\nb\n- one\n- two\nc")
        let lines = NSRange(location: location(editor, line: 2, column: 0), length: ("one\ntwo\n" as NSString).length)
        editor.controller.move(lines, to: location(editor, line: 1, column: 0))
        #expect(editor.markdown == "a\n- one\n- two\nb\nc")
    }

    @Test func wholeLinesDroppedOnALineGoBelowIt() {
        let editor = EditorHarness("1. one\n2. two\na\nb")
        let lines = NSRange(location: 0, length: ("one\ntwo\n" as NSString).length)
        editor.controller.move(lines, to: location(editor, line: 2, column: 1))
        #expect(editor.markdown == "a\n1. one\n2. two\nb")
    }

    @Test func droppingTextOnItselfDoesNothing() {
        let editor = EditorHarness("one two")
        let couldUndo = editor.textView.undoManager?.canUndo
        editor.controller.move(range(editor, line: 0, 0..<3), to: 2)
        editor.controller.move(range(editor, line: 0, 0..<3), to: 3)
        #expect(editor.markdown == "one two")
        #expect(editor.textView.undoManager?.canUndo == couldUndo)
    }

    @Test func oneUndoPutsItBack() {
        let editor = EditorHarness("- apple\n- **banana** split\nplain text here")
        editor.controller.move(range(editor, line: 1, 0..<12), to: location(editor, line: 2, column: 5))
        let moved = editor.markdown
        editor.undo()
        #expect(editor.markdown == "- apple\n- **banana** split\nplain text here")
        editor.redo()
        #expect(editor.markdown == moved)
    }

    @Test func oneUndoPutsLinesBack() {
        let editor = EditorHarness("a\nb\n- one\n- two\nc")
        let lines = NSRange(location: location(editor, line: 2, column: 0), length: ("one\ntwo\n" as NSString).length)
        editor.controller.move(lines, to: 0)
        editor.undo()
        #expect(editor.markdown == "a\nb\n- one\n- two\nc")
        editor.redo()
        #expect(editor.markdown == "- one\n- two\na\nb\nc")
    }

    @Test func aDropIsSaved() {
        let editor = EditorHarness("- apple\nplain")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        editor.controller.move(range(editor, line: 1, 0..<5), to: location(editor, line: 0, column: 5))
        editor.controller.reportPendingChange()
        #expect(reported == [editor.markdown + "\n"])
        #expect(editor.markdown.hasPrefix("- appleplain"))
    }
}

/// Part of a line copies as just its text, as in Notion: a word copied from a list item or a
/// heading and pasted into a sentence brought the `- ` or `# ` along.
struct PartOfALineCopyTests {
    @Test func partOfAListItemCopiesAsText() {
        let editor = EditorHarness("- **banana** split")
        editor.select(from: (0, 0), to: (0, 6))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "**banana**")
    }

    @Test func aHeadingsTextCopiesAsText() {
        let editor = EditorHarness("# Title")
        editor.select(from: (0, 0), to: (0, 5))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "Title")
    }

    @Test func itPastesIntoASentence() {
        let editor = EditorHarness("- [ ] buy milk\nget some please")
        editor.select(from: (0, 0), to: (0, 3))
        editor.controller.copySelection()
        editor.moveCaret(line: 1, column: 4)
        editor.controller.paste(UIPasteboard.general.string ?? "")
        #expect(editor.markdown == "- [ ] buy milk\nget buysome please")
    }

    @Test func textThatLooksLikeAMarkerStaysText() {
        let editor = EditorHarness("# 1. not a list")
        editor.select(from: (0, 0), to: (0, 13))
        editor.controller.copySelection()
        editor.moveCaret(line: 0)
        editor.type("\n")
        editor.controller.paste(UIPasteboard.general.string ?? "")
        #expect(editor.markdown == "# 1. not a list\n1\\. not a list")
    }
}

/// Anything else UIKit changes on its own, with no word to the delegate (Writing Tools, say),
/// is still styled and saved.
@MainActor
struct UnannouncedEditTests {
    @Test func itIsSaved() async {
        let editor = EditorHarness("- apple\nplain")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        let storage = editor.textView.textStorage
        storage.replaceCharacters(in: NSRange(location: 1, length: 3), with: "PPL")
        for _ in 0..<100 where reported.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported == ["- aPPLe\nplain\n"])
    }

    @Test func textPutAtTheStartOfALineJoinsIt() async {
        let editor = EditorHarness("- apple\nplain")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        let storage = editor.textView.textStorage
        let heading = NSAttributedString(string: "big ", attributes: BlockAttributes(kind: .heading1).dictionary)
        storage.insert(heading, at: ("apple\n" as NSString).length)
        for _ in 0..<100 where reported.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported == ["- apple\nbig plain\n"])
    }
}

/// A whole line, its line break included, still copies as the line it is.
struct WholeLineCopyTests {
    @Test func aWholeLineKeepsItsKind() {
        let editor = EditorHarness("- apple\nplain")
        editor.select(from: (0, 0), to: (1, 0))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "- apple")
    }
}

/// The editor's own edits, from the format bar or a checkbox, commit what an input method is
/// composing first, as a tap elsewhere in the text does.
@MainActor
struct EditsWhileComposingTests {
    @Test func aFormatButtonCommitsIt() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0)
        editor.startComposing("ni")
        editor.controller.perform(.bullet)
        #expect(editor.textView.markedTextRange == nil)
        #expect(editor.markdown == "- abni")
        editor.compose(["h"], commit: "\u{597D}")
        #expect(editor.markdown == "- abni\u{597D}")
    }

    @Test func onAnEmptyLineTheListStays() {
        let editor = EditorHarness()
        editor.startComposing("ni")
        editor.controller.perform(.ordered)
        editor.compose(["hao"], commit: "\u{597D}")
        #expect(editor.markdown == "1. ni\u{597D}")
    }

    @Test func aCheckboxCommitsIt() {
        let editor = EditorHarness("- [ ] ab")
        editor.moveCaret(line: 0)
        editor.startComposing("ni")
        editor.controller.toggleTodo(at: 0)
        #expect(editor.textView.markedTextRange == nil)
        #expect(editor.markdown == "- [x] abni")
    }

    /// Clear empties the page while a word is being composed: the dot must show it empty.
    @Test func loadingAPageDropsIt() {
        let editor = EditorHarness("ab")
        var empty: [Bool] = []
        editor.controller.onEmptyChange = { empty.append($0) }
        editor.moveCaret(line: 0)
        editor.startComposing("ni")
        editor.controller.load(markdown: "")
        #expect(editor.textView.markedTextRange == nil)
        #expect(empty.isEmpty)
        editor.type("!")
        #expect(editor.markdown == "!")
        #expect(empty == [false])
    }
}

/// Moving to another dot while a word is being composed commits it on the page it was on.
@MainActor
struct SwitchingPagesWhileComposingTests {
    @Test func theWordStaysAndIsSaved() async {
        let one = EditorHarness("- one")
        var reported: [String] = []
        one.controller.onChange = { reported.append($0) }
        let two = EditorController(dot: 1, accent: .systemBlue)
        two.textView.frame = one.window.bounds
        one.window.addSubview(two.textView)
        two.load(markdown: "two")
        one.moveCaret(line: 0)
        one.startComposing("ni")
        two.focus()
        #expect(one.textView.markedTextRange == nil)
        for _ in 0..<100 where reported.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported == ["- oneni\n"])
        one.controller.focus()
        one.moveCaret(line: 0)
        one.compose(["hao"], commit: "\u{597D}")
        #expect(one.markdown == "- oneni\u{597D}")
    }
}

/// Lines selected from the start of one to the end of another move as lines, though the
/// selection holds no line break after the last one.
@MainActor
struct LinesWithoutTheirLastLineBreakTests {
    private func location(_ editor: EditorHarness, line: Int, column: Int) -> Int {
        let lines = editor.textView.text.components(separatedBy: "\n")
        return lines[..<line].reduce(0) { $0 + ($1 as NSString).length + 1 } + column
    }

    @Test func linesInTheMiddle() {
        let editor = EditorHarness("a\n- b\n- c\nd")
        let start = location(editor, line: 1, column: 0)
        editor.controller.move(NSRange(location: start, length: location(editor, line: 2, column: 1) - start), to: 0)
        #expect(editor.markdown == "- b\n- c\na\nd")
    }

    @Test func thePagesLastLines() {
        let editor = EditorHarness("a\n- b\n- c")
        let start = location(editor, line: 1, column: 0)
        editor.controller.move(NSRange(location: start, length: location(editor, line: 2, column: 1) - start), to: 0)
        #expect(editor.markdown == "- b\n- c\na")
        editor.undo()
        #expect(editor.markdown == "a\n- b\n- c")
    }

    @Test func thePagesLastLinesDroppedOnTheLineAbove() {
        let editor = EditorHarness("a\n- b\n- c")
        let start = location(editor, line: 1, column: 0)
        let lines = NSRange(location: start, length: location(editor, line: 2, column: 1) - start)
        let couldUndo = editor.textView.undoManager?.canUndo
        editor.controller.move(lines, to: location(editor, line: 0, column: 1))
        #expect(editor.markdown == "a\n- b\n- c")
        #expect(editor.textView.undoManager?.canUndo == couldUndo)
    }

    @Test func linesDroppedJustBelowThemselvesStay() {
        let editor = EditorHarness("a\nb\nc\nd")
        let couldUndo = editor.textView.undoManager?.canUndo
        editor.controller.move(NSRange(location: 2, length: 3), to: location(editor, line: 3, column: 0))
        #expect(editor.markdown == "a\nb\nc\nd")
        #expect(editor.textView.undoManager?.canUndo == couldUndo)
    }

    @Test func oneLinesTextStaysText() {
        let editor = EditorHarness("a\n- b\nc")
        editor.controller.move(NSRange(location: 2, length: 1), to: 0)
        #expect(editor.markdown == "ba\n-\nc")
    }
}

/// Lines dropped where the caret already was, with a divider last among them: the caret was
/// set to where it had been, so UIKit said nothing, and it stayed on the divider.
@MainActor
struct CaretAfterDroppingADividerTests {
    @Test func theCaretStepsOffTheDivider() {
        let editor = EditorHarness("t\nu\n- h\n---\np")
        let text = editor.textView.text as NSString
        editor.controller.move(NSRange(location: 4, length: 3), to: 1)
        #expect(editor.markdown == "t\n- h\n---\nu\np")
        let caret = editor.textView.selectedRange.location
        let line = (editor.textView.text as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        let kind = AttributedDocument.document(from: editor.textView.textStorage, in: line).blocks.first?.kind
        #expect(kind != .divider, "caret at \(caret) in \(text)")
    }
}
