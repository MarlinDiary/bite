import Testing
import UIKit
import BiteKit
@testable import Bite

/// Where a list starts counting, and how deep its items sit, stay what the Markdown can say.
struct ListStructureTests {
    @Test func newFirstItemTakesOverTheStart() {
        let editor = EditorHarness("5. a\n6. b")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\n")
        #expect(editor.markdown == "5.\n6. a\n7. b")
    }

    @Test func aStartNumberComesBackWhenItsListSplitsOffAgain() {
        let editor = EditorHarness("1. a\n\n5. b")
        editor.moveCaret(line: 1)
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. a\n2.\n3. b")
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. a\n\n5. b")
    }

    @Test func turningAParentIntoTextPullsItsChildrenUp() {
        let editor = EditorHarness("- a\n    - b\n        - c\n    - d")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bullet)
        #expect(editor.markdown == "a\n- b\n    - c\n- d")
        #expect((0...3).map(editor.indent(line:)) == [0, 0, 1, 0])
        editor.undo()
        #expect(editor.markdown == "- a\n    - b\n        - c\n    - d")
        #expect((0...3).map(editor.indent(line:)) == [0, 1, 2, 1])
        editor.redo()
        #expect((0...3).map(editor.indent(line:)) == [0, 0, 1, 0])
    }

    @Test func outdentingAParentBringsItsChildren() {
        let editor = EditorHarness("- a\n    - b\n        - c")
        editor.moveCaret(line: 1)
        editor.controller.perform(.outdent)
        #expect((0...2).map(editor.indent(line:)) == [0, 0, 1])
        editor.undo()
        #expect((0...2).map(editor.indent(line:)) == [0, 1, 2])
    }

    @Test func deletingAParentPullsItsChildrenUp() {
        let editor = EditorHarness("text\n- a\n    - b")
        editor.select(from: (0, 4), to: (1, 1))
        editor.backspace()
        #expect(editor.markdown == "text\n- b")
        #expect(editor.indent(line: 1) == 0)
        editor.undo()
        #expect(editor.markdown == "text\n- a\n    - b")
        #expect(editor.indent(line: 2) == 1)
    }
}

/// Code stays code on its way through the clipboard, in both directions.
struct ClipboardTests {
    @Test func pastingIntoCodeKeepsItCode() {
        let editor = EditorHarness("```\nx\n```")
        editor.moveCaret(line: 0)
        editor.controller.paste("# not a heading\r\n- nor a list *or* `span`")
        #expect(editor.markdown == "```\nx# not a heading\n- nor a list *or* `span`\n```")
    }

    @Test func pastingFencedCodeIntoCodeLeavesTheFenceOut() {
        let editor = EditorHarness("```\nx\n```")
        editor.moveCaret(line: 0)
        editor.controller.paste("```swift\nlet y = 2\n```")
        #expect(editor.markdown == "```\nxlet y = 2\n```")
    }

    @Test func copyingCodeGivesJustTheCode() {
        let editor = EditorHarness("```swift\nlet a = 1\nlet b = 2\n```")
        editor.selectAll()
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "let a = 1\nlet b = 2")
        #expect(EditorController.copiedMarkdown == "```swift\nlet a = 1\nlet b = 2\n```")
    }

    @Test func copiedCodePastesBackAsCode() {
        let editor = EditorHarness("```\n# a\n```\n\n")
        editor.select(from: (0, 0), to: (0, 3))
        editor.controller.copySelection()
        editor.moveCaret(line: 1)
        editor.textView.paste(nil)
        #expect(editor.markdown == "```\n# a\n# a\n```")
    }

    @Test func copyingTextLeavesNoCodeBehind() {
        let editor = EditorHarness("```\ncode\n```\ntext")
        editor.select(from: (0, 0), to: (0, 4))
        editor.controller.copySelection()
        editor.select(from: (1, 0), to: (1, 4))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "text")
        #expect(EditorController.copiedMarkdown == nil)
    }

    @Test func copyingPartOfAListKeepsItsNumbers() {
        let editor = EditorHarness("1. a\n2. b\n3. c")
        editor.select(from: (1, 0), to: (2, 1))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "2. b\n3. c")
    }
}

/// A line joined from two carries attributes from both until they're set again for the whole
/// line: the line break comes from the line that was below.
struct JoinedLineTests {
    private func ordinal(_ editor: EditorHarness, line: Int) -> Int? {
        let text = editor.textView.text as NSString
        var location = 0
        for _ in 0..<line { location = NSMaxRange(text.paragraphRange(for: NSRange(location: location, length: 0))) }
        return editor.textView.textStorage.attribute(.biteOrdinal, at: location, effectiveRange: nil) as? Int
    }

    /// The user's report: 1–4, Return, backspace to go back up to 4, type. The 4 turned to 0.
    @Test func backToTheLastItemAndTyping() {
        let editor = EditorHarness("1. a\n2. b\n3. c\n4. d")
        editor.moveCaret(line: 3)
        editor.type("\n", separateEvents: true)
        editor.backspace()
        editor.backspace()
        editor.type("x", separateEvents: true)
        #expect(editor.markdown == "1. a\n2. b\n3. c\n4. dx")
        #expect(ordinal(editor, line: 3) == 4)
    }

    @Test func joiningTheNextItemKeepsTheNumber() {
        let editor = EditorHarness("1. a\n2. b\n3. c")
        editor.moveCaret(line: 2, column: 0)
        editor.backspace()
        editor.backspace()
        editor.type("x", separateEvents: true)
        #expect(ordinal(editor, line: 1) == 2)
    }

    @Test func joiningAParagraphOntoAnItem() {
        let editor = EditorHarness("1. a\n2. b\ntext")
        editor.moveCaret(line: 2, column: 0)
        editor.backspace()
        editor.type("y", separateEvents: true)
        #expect(ordinal(editor, line: 1) == 2)
        // The caret stays where the lines met.
        #expect(editor.markdown == "1. a\n2. bytext")
    }

    @Test func joiningKeepsALettersStyle() {
        let editor = EditorHarness("a. one\nb. two")
        editor.moveCaret(line: 1)
        editor.type("\n", separateEvents: true)
        editor.backspace()
        editor.backspace()
        editor.type("x", separateEvents: true)
        let storage = editor.textView.textStorage
        #expect(storage.attribute(.biteShownStyle, at: storage.length - 2, effectiveRange: nil) as? String == NumberStyle.letters.rawValue)
        #expect(editor.markdown == "a. one\nb. twox")
    }

    @Test func joiningAQuoteLineKeepsItsBar() {
        let editor = EditorHarness("> a\n> b\ntext")
        editor.moveCaret(line: 2, column: 0)
        editor.backspace()
        editor.type("z", separateEvents: true)
        let storage = editor.textView.textStorage
        let positions = [0, 4, storage.length - 2].map { storage.attribute(.biteRunPosition, at: $0, effectiveRange: nil) as? Int }
        #expect(positions == [RunPosition.first.rawValue, RunPosition.last.rawValue, RunPosition.last.rawValue])
    }

    /// A line break never carries bold or italic, so the empty line Return leaves stays plain.
    @Test func anEmptyLineAfterBoldIsPlain() {
        let editor = EditorHarness("**bold**")
        editor.moveCaret(line: 0)
        editor.type("\n", separateEvents: true)
        let storage = editor.textView.textStorage
        let font = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == false)
    }

    @Test func strikethroughOverLinesLeavesTheLineBreaks() {
        let editor = EditorHarness("ab\ncd")
        editor.selectAll()
        editor.controller.perform(.strikethrough)
        let storage = editor.textView.textStorage
        #expect(storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) == nil)
        #expect(editor.markdown == "~~ab~~\n~~cd~~")
    }
}
