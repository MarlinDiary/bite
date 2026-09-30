import Testing
import UIKit
@testable import Bite

/// Typing as a Notion user expects, case by case. Characters typed by Chinese keyboards are
/// written as escapes: U+300B is the right double angle bracket, U+3010 and U+3011 are the
/// lenticular brackets, U+3002 the ideographic full stop, U+FF09 the full-width right
/// parenthesis, U+00B7 the middle dot and U+FF5E the full-width tilde.
struct BlockShortcutEdgeTests {
    @Test func bulletThenBracketsMakesATodo() {
        let editor = EditorHarness()
        editor.type("- [ ] task")
        #expect(editor.markdown == "- [ ] task")
    }

    @Test func starBulletThenCheckedBrackets() {
        let editor = EditorHarness()
        editor.type("* [x] done")
        #expect(editor.markdown == "- [x] done")
    }

    @Test func numberInsideANestedItemKeepsItsLevel() {
        let editor = EditorHarness("- a\n    - [ ] b")
        editor.moveCaret(line: 1, column: 0)
        editor.type("1. ")
        #expect(editor.markdown == "- a\n    1. b")
    }

    @Test func headingOnAParentPullsItsChildrenUp() {
        let editor = EditorHarness("- a\n    - b")
        editor.moveCaret(line: 0, column: 0)
        editor.type("# ")
        #expect(editor.markdown == "# a\n- b")
        #expect(editor.indent(line: 1) == 0)
    }

    @Test(arguments: ["0. zero", "10. ten"])
    func listsStartAtAnyNumber(_ typed: String) {
        let editor = EditorHarness()
        editor.type(typed + "\nnext")
        let start = Int(typed.prefix(while: \.isNumber))!
        #expect(editor.markdown == "\(typed)\n\(start + 1). next")
    }

    @Test func backticksInAListItemMakeCode() {
        let editor = EditorHarness()
        editor.type("- ```x")
        #expect(editor.markdown == "```\nx\n```")
    }

    @Test func dashesInAListItemMakeADivider() {
        let editor = EditorHarness()
        editor.type("- ---after")
        #expect(editor.markdown == "---\nafter")
    }

    @Test func codeIsTypedAsItIs() {
        let editor = EditorHarness("```\nx\n```\ntext")
        editor.moveCaret(line: 0)
        #expect(editor.textView.isTypingCode)
        #expect(editor.textView.smartQuotesType == .no)
        editor.moveCaret(line: 1)
        #expect(!editor.textView.isTypingCode)
        #expect(editor.textView.smartQuotesType == .default)
    }

    @Test func quoteFromAChineseKeyboard() {
        let editor = EditorHarness()
        editor.type("\u{300B} said")
        #expect(editor.markdown == "> said")
    }

    @Test(arguments: ["\u{3010}\u{3011} ", "\u{3010} \u{3011} "])
    func todoFromAChineseKeyboard(_ marker: String) {
        let editor = EditorHarness()
        editor.type(marker + "task")
        #expect(editor.markdown == "- [ ] task")
    }

    @Test(arguments: ["1\u{3002} ", "1\u{FF09} "])
    func numberFromAChineseKeyboard(_ marker: String) {
        let editor = EditorHarness()
        editor.type(marker + "one\ntwo")
        #expect(editor.markdown == "1. one\n2. two")
    }

    @Test func codeBlockFromMiddleDots() {
        let editor = EditorHarness()
        editor.type("\u{00B7}\u{00B7}\u{00B7}let x")
        #expect(editor.markdown == "```\nlet x\n```")
    }

    @Test func middleDotsCloseACodeBlock() {
        let editor = EditorHarness()
        editor.type("```x\n\u{00B7}\u{00B7}\u{00B7}after")
        #expect(editor.markdown == "```\nx\n```\nafter")
    }

    @Test func aNameWithMiddleDotsStaysText() {
        let editor = EditorHarness()
        editor.type("Jean\u{00B7}Paul\u{00B7}Sartre")
        #expect(editor.markdown == "Jean\u{00B7}Paul\u{00B7}Sartre")
    }
}

struct InlineShortcutEdgeTests {
    @Test func fullWidthTildesStrikeThrough() {
        let editor = EditorHarness()
        editor.type("\u{FF5E}\u{FF5E}gone\u{FF5E}\u{FF5E} kept")
        #expect(editor.markdown == "~~gone~~ kept")
    }

    @Test func singleFullWidthTildeStaysText() {
        let editor = EditorHarness()
        editor.type("fine\u{FF5E} thanks\u{FF5E}")
        #expect(editor.markdown == "fine\u{FF5E} thanks\u{FF5E}")
    }

    @Test func underscoresMakeItalic() {
        let editor = EditorHarness()
        editor.type("_it_ after")
        #expect(editor.markdown == "*it* after")
    }

    @Test func doubleUnderscoresMakeBold() {
        let editor = EditorHarness()
        editor.type("__bold__ after")
        #expect(editor.markdown == "**bold** after")
    }

    @Test func underscoresInsideAWordStayText() {
        let editor = EditorHarness()
        editor.type("snake_case_name")
        #expect(editor.markdown == "snake_case_name")
    }

    @Test func boldAroundComposedText() {
        let editor = EditorHarness()
        editor.type("**")
        editor.compose(["w", "wo", "wor"], commit: "word")
        editor.type("**")
        #expect(editor.markdown == "**word**")
    }
}

struct InputMethodEdgeTests {
    /// The keyboard asks about the whole selection before it starts composing, so the first
    /// letter has to go to the input method, not in as plain text.
    @Test func composingOverSeveralLines() {
        let editor = EditorHarness("- a\n- b")
        editor.selectAll()
        editor.compose(["n", "ni"], commit: "x")
        #expect(editor.markdown == "- x")
        #expect(editor.textView.markedTextRange == nil)
    }

    @Test func composingInANestedItemAfterReturn() {
        let editor = EditorHarness("- a\n    - b\n- c")
        editor.moveCaret(line: 1)
        editor.type("\n", separateEvents: true)
        editor.compose(["h", "he"], commit: "y")
        editor.type("\n", separateEvents: true)
        editor.compose(["z"], commit: "z")
        #expect(editor.markdown == "- a\n    - b\n    - y\n    - z\n- c")
    }

    @Test func italicButtonThenComposing() {
        let editor = EditorHarness("a ")
        editor.moveCaret(line: 0)
        editor.controller.perform(.italic)
        editor.compose(["w", "wo"], commit: "word")
        #expect(editor.markdown == "a *word*")
    }

    @Test func boldButtonThenComposingTwice() {
        let editor = EditorHarness()
        editor.controller.perform(.bold)
        editor.compose(["w"], commit: "w")
        editor.compose(["x"], commit: "x")
        #expect(editor.markdown == "**wx**")
    }

    @Test func composingRightAfterAShortcut() {
        let editor = EditorHarness()
        editor.type("1. ", separateEvents: true)
        editor.compose(["w", "wo"], commit: "w")
        editor.type("\n")
        editor.compose(["n"], commit: "n")
        #expect(editor.markdown == "1. w\n2. n")
    }
}

struct ReturnEdgeTests {
    @Test func returnOverASelectionInACheckedTodo() {
        let editor = EditorHarness("- [x] abc")
        editor.select(from: (0, 1), to: (0, 2))
        editor.type("\n")
        #expect(editor.markdown == "- [x] a\n- [ ] c")
    }

    @Test func returnOverASelectionInAHeading() {
        let editor = EditorHarness("# abc")
        editor.select(from: (0, 1), to: (0, 2))
        editor.type("\n")
        #expect(editor.markdown == "# a\nc")
    }

    @Test func returnOverASelectionInAParagraph() {
        let editor = EditorHarness("abc")
        editor.select(from: (0, 1), to: (0, 2))
        editor.type("\n")
        #expect(editor.markdown == "a\nc")
        editor.undo()
        #expect(editor.markdown == "abc")
    }

    @Test func returnInAStartedListKeepsCounting() {
        let editor = EditorHarness("3. a")
        editor.type("\nb")
        #expect(editor.markdown == "3. a\n4. b")
    }

    @Test func emptyItemInTheMiddleSplitsTheList() {
        let editor = EditorHarness("1. a\n2. b\n3. c")
        editor.moveCaret(line: 0)
        editor.type("\n\n")
        #expect(editor.markdown == "1. a\n\n1. b\n2. c")
    }

    @Test func returnThreeTimesLeavesANestedList() {
        let editor = EditorHarness("- a\n    - b")
        editor.moveCaret(line: 1)
        editor.type("\n\n\n")
        // Out of the nested list, out of the list, and a plain paragraph is left.
        #expect(editor.markdown == "- a\n    - b\n")
        #expect(editor.caret == 4)
    }
}

struct DividerEdgeTests {
    @Test func theCaretStepsOffADivider() {
        let editor = EditorHarness("above\n---\nbelow")
        editor.moveCaret(line: 0, column: 0)
        editor.textView.selectedRange = NSRange(location: 6, length: 0)
        #expect(editor.caret == 7)
        editor.type("x")
        #expect(editor.markdown == "above\n---\nxbelow")
    }

    @Test func comingUpFromBelowItLandsAbove() {
        let editor = EditorHarness("above\n---\nbelow")
        editor.textView.selectedRange = NSRange(location: 8, length: 0)
        editor.textView.selectedRange = NSRange(location: 6, length: 0)
        #expect(editor.caret == 5)
    }

    @Test func aDividerAtTheEndKeepsTheCaretSoItCanGo() {
        let editor = EditorHarness("above\n---")
        editor.textView.selectedRange = NSRange(location: 6, length: 0)
        #expect(editor.caret == 6)
        editor.backspace()
        #expect(editor.markdown == "above\n")
    }

    @Test func backspaceOnAnEmptyLineBelowADividerDeletesIt() {
        let editor = EditorHarness("above\n---\n\nbelow")
        editor.moveCaret(line: 2, column: 0)
        editor.backspace()
        #expect(editor.markdown == "above\n\nbelow")
        #expect(editor.caret == 6)
        editor.undo()
        #expect(editor.markdown == "above\n---\n\nbelow")
    }

    @Test func backspaceBelowADividerKeepsTheLinesKind() {
        let editor = EditorHarness("---\n- [ ] task")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace(2)
        #expect(editor.markdown == "task")
    }

    @Test func fullWidthSpaceConfirmsAShortcut() {
        let editor = EditorHarness()
        editor.type("-\u{3000}item")
        #expect(editor.markdown == "- item")
    }
}

struct BackspaceEdgeTests {
    @Test func insideACodeBlockJoinsTheLineAbove() {
        let editor = EditorHarness("```\na\nb\n```")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "```\nab\n```")
        editor.undo()
        #expect(editor.markdown == "```\na\nb\n```")
    }

    @Test func atTheStartOfACodeBlockMakesAParagraph() {
        let editor = EditorHarness("```\na\nb\n```")
        editor.moveCaret(line: 0, column: 0)
        editor.backspace()
        #expect(editor.markdown == "a\n```\nb\n```")
    }

    @Test func afterADividerRemovesIt() {
        let editor = EditorHarness("---\ntext")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "text")
    }

    @Test func emptyLineUnderAHeadingGoesAway() {
        let editor = EditorHarness("# Title\n\nbody")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "# Title\nbody")
        #expect(editor.caret == 5)
    }

    @Test func twiceOnAnEmptyItemRemovesIt() {
        let editor = EditorHarness("a\n- ")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace(2)
        #expect(editor.markdown == "a")
    }
}

struct IndentEdgeTests {
    @Test func indentingAParentBringsItsChildren() {
        let editor = EditorHarness("- a\n- b\n    - c\n        - d\n- e")
        editor.moveCaret(line: 1)
        editor.type("\t")
        #expect(editor.markdown == "- a\n    - b\n        - c\n            - d\n- e")
        editor.undo()
        #expect(editor.markdown == "- a\n- b\n    - c\n        - d\n- e")
    }

    @Test func indentingTheParentAndItsChildTogether() {
        let editor = EditorHarness("- a\n- b\n    - c")
        editor.select(from: (1, 0), to: (2, 1))
        editor.controller.perform(.indent)
        #expect(editor.markdown == "- a\n    - b\n        - c")
    }

    @Test func outdentingAParentBringsItsChildren() {
        let editor = EditorHarness("- a\n    - b\n        - c\n    - d")
        editor.moveCaret(line: 1)
        editor.controller.perform(.outdent)
        #expect(editor.markdown == "- a\n- b\n    - c\n    - d")
    }

    @Test func tabInAParagraphTypesATab() {
        let editor = EditorHarness("text")
        editor.moveCaret(line: 0)
        editor.type("\t")
        #expect(editor.markdown == "text\t")
    }

    @Test func tabInCodeTypesATab() {
        let editor = EditorHarness("```\nx\n```")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\t")
        #expect(editor.markdown == "```\n\tx\n```")
    }

    @Test func indentedNumbersRestartAtTheNewLevel() {
        let editor = EditorHarness("1. a\n2. b\n3. c")
        editor.moveCaret(line: 1)
        editor.type("\t")
        #expect(editor.markdown == "1. a\n    1. b\n2. c")
    }
}

struct FormatBarEdgeTests {
    @Test func bulletsOnSeveralParagraphs() {
        let editor = EditorHarness("a\nb\nc")
        editor.select(from: (0, 0), to: (2, 1))
        editor.controller.perform(.bullet)
        #expect(editor.markdown == "- a\n- b\n- c")
        editor.controller.perform(.bullet)
        #expect(editor.markdown == "a\nb\nc")
    }

    @Test func numbersOnABulletListKeepItsLevels() {
        let editor = EditorHarness("- a\n    - b")
        editor.selectAll()
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. a\n    1. b")
    }

    @Test func codeDropsInlineStylesAndUndoBringsThemBack() {
        let editor = EditorHarness("a **b** c")
        editor.controller.perform(.code)
        #expect(editor.markdown == "```\na b c\n```")
        editor.undo()
        #expect(editor.markdown == "a **b** c")
    }

    @Test func quoteOnAParentPullsItsChildrenUp() {
        let editor = EditorHarness("- a\n    - b")
        editor.moveCaret(line: 0)
        editor.controller.perform(.quote)
        #expect(editor.markdown == "> a\n- b")
    }

    @Test func boldAcrossTwoLines() {
        let editor = EditorHarness("- ab\n- cd")
        editor.select(from: (0, 1), to: (1, 1))
        editor.controller.perform(.bold)
        #expect(editor.markdown == "- a**b**\n- **c**d")
    }
}

struct PasteEdgeTests {
    @Test func aListPastedIntoANestedItemStaysNested() {
        let editor = EditorHarness("- a\n    - ")
        editor.moveCaret(line: 1)
        editor.controller.paste("- p\n- q\n    - r")
        #expect(editor.markdown == "- a\n    - p\n    - q\n        - r")
    }

    @Test func plainLinesPastedIntoAnItem() {
        let editor = EditorHarness("- xy")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("a\nb")
        #expect(editor.markdown == "- xa\nby")
    }
}

/// Dividers in a row: the caret passes them all at once. One at a time, coming up from below two
/// of them sent it back and forth between them without end, and the app crashed.
struct DividersInARowTests {
    private func location(_ editor: EditorHarness, of text: String) -> Int {
        (editor.textView.text as NSString).range(of: text).location
    }

    @Test func comingUpFromBelowLandsAboveThem() {
        let editor = EditorHarness("top\n---\n---\nend")
        editor.moveCaret(line: 3, column: 0)
        // Up onto the second divider.
        editor.textView.selectedRange = NSRange(location: location(editor, of: "end") - 1, length: 0)
        #expect(editor.caret == location(editor, of: "top") + 3)
    }

    @Test func goingDownLandsBelowThem() {
        let editor = EditorHarness("top\n---\n---\n---\nend")
        editor.moveCaret(line: 0)
        editor.textView.selectedRange = NSRange(location: 4, length: 0)
        #expect(editor.caret == location(editor, of: "end"))
    }

    @Test func atTheTopOfThePageItGoesBelowThem() {
        let editor = EditorHarness("---\n---\nend")
        editor.moveCaret(line: 2, column: 0)
        editor.textView.selectedRange = NSRange(location: 1, length: 0)
        #expect(editor.caret == location(editor, of: "end"))
    }

    /// The last divider on the page keeps the caret, so backspace can take it away.
    @Test func atTheEndOfThePageTheLastOneKeepsTheCaret() {
        let editor = EditorHarness("top\n---\n---")
        editor.moveCaret(line: 0)
        editor.textView.selectedRange = NSRange(location: 4, length: 0)
        #expect(editor.caret == 5)
        // And coming up from it goes above them.
        editor.textView.selectedRange = NSRange(location: 4, length: 0)
        #expect(editor.caret == 3)
    }

    @Test func aPageOfNothingButDividers() {
        let editor = EditorHarness("---\n---\n---")
        editor.textView.selectedRange = NSRange(location: 0, length: 0)
        #expect(editor.caret == 2)
    }
}
