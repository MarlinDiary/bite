import Testing
import UIKit
import BiteKit
@testable import Bite

/// One line pasted among text goes in as text: a marker at its start only makes a block on a
/// line of its own. U+201C is the curly quotation mark that smart quotes type.
struct PasteAsTextTests {
    @Test func aDashStaysADash() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("- note")
        #expect(editor.markdown == "a- noteb")
    }

    @Test func aStarStays() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("*")
        #expect(editor.textView.text == "a*b\n")
    }

    @Test func aHashStays() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("# 1")
        #expect(editor.textView.text == "a# 1b\n")
    }

    @Test func dashesStay() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("---")
        #expect(editor.textView.text == "a---b\n")
    }

    @Test func aNumberAtTheEndOfTextStays() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0)
        editor.controller.paste("1. first")
        #expect(editor.textView.text == "ab1. first\n")
    }

    @Test func aQuoteMarkerInAHeadingStays() {
        let editor = EditorHarness("# ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("> q")
        #expect(editor.markdown == "# a> qb")
    }

    @Test func boldStillComesThrough() {
        let editor = EditorHarness("ab")
        editor.moveCaret(line: 0, column: 1)
        editor.controller.paste("**x**")
        #expect(editor.markdown == "a**x**b")
    }

    @Test func spacesAtEitherEndStay() {
        let editor = EditorHarness("hello")
        editor.moveCaret(line: 0)
        editor.controller.paste(" there ")
        editor.type("world")
        #expect(editor.textView.text == "hello there world\n")
    }

    @Test func onAnEmptyLineAMarkerMakesTheBlock() {
        let editor = EditorHarness("")
        editor.controller.paste("- note")
        #expect(editor.markdown == "- note")
    }

    @Test func overAWholeLineAMarkerMakesTheBlock() {
        let editor = EditorHarness("abc\ndef")
        editor.select(from: (0, 0), to: (0, 3))
        editor.controller.paste("- x")
        #expect(editor.markdown == "- x\ndef")
    }

    @Test func intoAnEmptyItemTextJoinsTheItem() {
        let editor = EditorHarness("- a\n-")
        editor.moveCaret(line: 1)
        editor.controller.paste("b")
        #expect(editor.markdown == "- a\n- b")
    }

    @Test func linesPastedIntoAHeadingSplitIt() {
        let editor = EditorHarness("# abcd")
        editor.moveCaret(line: 0, column: 2)
        editor.controller.paste("x\n- y")
        #expect(editor.markdown == "# abx\n- ycd")
    }
}

/// Shortcuts as Notion has them, and where Bite deliberately differs.
struct NotionShortcutTests {
    @Test func aQuotationMarkMakesAQuote() {
        let editor = EditorHarness()
        editor.type("\" q")
        #expect(editor.markdown == "> q")
    }

    @Test func aCurlyQuotationMarkMakesAQuote() {
        let editor = EditorHarness()
        editor.type("\u{201C} q")
        #expect(editor.markdown == "> q")
    }

    /// U+3000 is the full-width space of Chinese keyboards.
    @Test func aCurlyQuotationMarkAndAFullWidthSpace() {
        let editor = EditorHarness()
        editor.type("\u{201C}\u{3000}q")
        #expect(editor.markdown == "> q")
    }

    @Test func aQuotationMarkTurnsTextIntoAQuote() {
        let editor = EditorHarness("abc")
        editor.moveCaret(line: 0, column: 0)
        editor.type("\" ")
        #expect(editor.markdown == "> abc")
    }

    @Test func aQuotationBeforeTextStaysText() {
        let editor = EditorHarness()
        editor.type("\"Hi\" she said")
        #expect(editor.textView.text == "\"Hi\" she said\n")
    }

    @Test func aQuotationMarkInCodeStays() {
        let editor = EditorHarness("```\n\n```")
        editor.moveCaret(line: 0)
        editor.type("\" x")
        #expect(editor.markdown == "```\n\" x\n```")
    }

    @Test func undoGivesBackTheQuotationMark() {
        let editor = EditorHarness()
        editor.type("\" ", separateEvents: true)
        editor.undo()
        #expect(editor.textView.text == "\" \n")
    }

    @Test func backticksTurnTextIntoCode() {
        let editor = EditorHarness("abc")
        editor.moveCaret(line: 0, column: 0)
        editor.type("```")
        #expect(editor.markdown == "```\nabc\n```")
    }

    @Test func backticksTurnAnItemIntoCode() {
        let editor = EditorHarness("- abc")
        editor.moveCaret(line: 0, column: 0)
        editor.type("```")
        #expect(editor.markdown == "```\nabc\n```")
    }

    /// A divider holds no text.
    @Test func dashesBeforeTextStayText() {
        let editor = EditorHarness("abc")
        editor.moveCaret(line: 0, column: 0)
        editor.type("---")
        #expect(editor.textView.text == "---abc\n")
    }

    @Test func aHeadingOverATodo() {
        let editor = EditorHarness("- [x] a")
        editor.moveCaret(line: 0, column: 0)
        editor.type("# ")
        #expect(editor.markdown == "# a")
    }

    @Test func aQuoteOverAHeading() {
        let editor = EditorHarness("# a")
        editor.moveCaret(line: 0, column: 0)
        editor.type("> ")
        #expect(editor.markdown == "> a")
    }

    @Test func aDeeperHeadingOverAHeading() {
        let editor = EditorHarness("# a")
        editor.moveCaret(line: 0, column: 0)
        editor.type("## ")
        #expect(editor.markdown == "## a")
    }

    @Test func boldItalic() {
        let editor = EditorHarness()
        editor.type("***bi***")
        #expect(editor.markdown == "***bi***")
    }

    @Test func italicInsideBold() {
        let editor = EditorHarness("**ab**")
        editor.moveCaret(line: 0, column: 1)
        editor.type("*x*")
        #expect(editor.markdown == "**a*x*b**")
    }

    /// Notion strikes through with one tilde, but ranges are written with one all the time,
    /// in Chinese too, so it takes two here, as in Markdown.
    @Test func singleTildesStayText() {
        let editor = EditorHarness()
        editor.type("3~5 days, 6~8 days, ~5 min")
        #expect(editor.textView.text == "3~5 days, 6~8 days, ~5 min\n")
    }

    @Test func doubleTildesStrikeThrough() {
        let editor = EditorHarness()
        editor.type("a ~~s~~ b")
        #expect(editor.markdown == "a ~~s~~ b")
    }

    @Test func spacedTildesStayText() {
        let editor = EditorHarness()
        editor.type("a ~ b ~ c")
        #expect(editor.textView.text == "a ~ b ~ c\n")
    }
}

struct NotionKeyTests {
    @Test func splittingACheckedTodoLeavesTheRestUnchecked() {
        let editor = EditorHarness("- [x] abcd")
        editor.moveCaret(line: 0, column: 2)
        editor.type("\n")
        #expect(editor.markdown == "- [x] ab\n- [ ] cd")
    }

    @Test func backspaceInTheMiddleOfAQuoteSplitsIt() {
        let editor = EditorHarness("> a\n> b\n> c")
        editor.moveCaret(line: 1, column: 0)
        editor.backspace()
        #expect(editor.markdown == "> a\nb\n> c")
    }

    @Test func backspaceOnABlankLineInsideCode() {
        let editor = EditorHarness("```\na\n\nb\n```")
        editor.moveCaret(line: 1)
        editor.backspace()
        #expect(editor.markdown == "```\na\nb\n```")
    }

    @Test func anEmptyNestedNumberMovesUpAndCountsOn() {
        let editor = EditorHarness("1. a\n    1. b")
        editor.moveCaret(line: 1)
        editor.type("\n")
        editor.type("\n")
        editor.type("c")
        #expect(editor.markdown == "1. a\n    1. b\n2. c")
    }

    @Test func theCaretStepsOverTwoDividers() {
        let editor = EditorHarness("a\n---\n---\nb")
        editor.textView.selectedRange = NSRange(location: 1, length: 0)
        // Moving right from the end of "a".
        editor.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(editor.caret == (editor.textView.text as NSString).range(of: "b").location)
    }

    /// With a hardware keyboard, for what's typed next.
    @Test func commandBWorksAtTheCaret() {
        let editor = EditorHarness("a")
        editor.moveCaret(line: 0)
        let bold = #selector(UIResponderStandardEditActions.toggleBoldface(_:))
        #expect(editor.textView.canPerformAction(bold, withSender: UIKeyCommand(input: "b", modifierFlags: .command, action: bold)))
    }

    /// Down to an empty page and back, with no stray space left from the shortcut.
    @Test func undoAndRedoAllTheWay() {
        let editor = EditorHarness()
        editor.type("- a", separateEvents: true)
        editor.type("\n", separateEvents: true)
        editor.type("b", separateEvents: true)
        editor.type("\n", separateEvents: true)
        editor.type("\t", separateEvents: true)
        editor.type("c", separateEvents: true)
        #expect(editor.markdown == "- a\n- b\n    - c")
        for _ in 0..<12 { editor.undo() }
        #expect(editor.textView.text == "\n")
        for _ in 0..<12 { editor.redo() }
        #expect(editor.markdown == "- a\n- b\n    - c")
    }
}

/// Dividers hold no text, so the line buttons pass them by.
struct DividerInASelectionTests {
    @Test func bullets() {
        let editor = EditorHarness("a\n---\nb")
        editor.selectAll()
        editor.controller.perform(.bullet)
        #expect(editor.markdown == "- a\n---\n- b")
    }

    @Test func headings() {
        let editor = EditorHarness("a\n---\nb")
        editor.selectAll()
        editor.controller.perform(.heading)
        #expect(editor.markdown == "# a\n---\n# b")
    }

    @Test func bold() {
        let editor = EditorHarness("a\n---\nb")
        editor.selectAll()
        editor.controller.perform(.bold)
        #expect(editor.markdown == "**a**\n---\n**b**")
    }
}

struct LongPageTests {
    /// Deep lists from Markdown line up with the deepest level that indents, keeping their level.
    @Test func deepNestingLeavesRoomForText() {
        let markdown = (0..<14).map { String(repeating: "  ", count: $0) + "- l\($0)" }.joined(separator: "\n")
        let editor = EditorHarness(markdown)
        let storage = editor.textView.textStorage
        var widest: CGFloat = 0
        var location = 0
        for line in editor.textView.text.components(separatedBy: "\n").dropLast() {
            let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            widest = max(widest, style?.headIndent ?? 0)
            location += (line as NSString).length + 1
        }
        #expect(widest < editor.textView.textContainer.size.width / 2)
        #expect(editor.indent(line: 13) == 13)
    }

    @Test func tabStopsAtTheDeepestLevel() {
        let lines = (0...EditorTheme.deepestIndent).map { String(repeating: "    ", count: $0) + "- l\($0)" }
        let last = String(repeating: "    ", count: EditorTheme.deepestIndent) + "- x"
        let editor = EditorHarness((lines + [last]).joined(separator: "\n"))
        editor.moveCaret(line: lines.count)
        editor.type("\t")
        #expect(editor.indent(line: lines.count) == EditorTheme.deepestIndent)
    }

    /// Each keystroke took 45 ms or more when the whole page was read back every time.
    @Test func typingInALongPageIsQuick() {
        let markdown = (0..<3000).map { "Line \($0) with some words in it" }.joined(separator: "\n")
        let editor = EditorHarness(markdown)
        editor.moveCaret(line: 2999)
        let clock = ContinuousClock()
        let times = (0..<5).map { _ in clock.measure { editor.type("x") } }.sorted()
        #expect(times[2] < .milliseconds(25))
    }
}

/// Lists in letters and Roman numerals, started as in Notion. U+3002 is the ideographic full stop.
struct LetteredListTests {
    @Test func typingAStartsALetteredList() {
        let editor = EditorHarness()
        editor.type("a. one\ntwo\nthree")
        #expect(editor.markdown == "a. one\nb. two\nc. three")
    }

    /// The keyboard capitalizes the start of a line.
    @Test func typingACapitalStartsACapitalList() {
        let editor = EditorHarness()
        editor.type("A. one\ntwo")
        #expect(editor.markdown == "A. one\nB. two")
    }

    @Test func typingIStartsARomanList() {
        let editor = EditorHarness()
        editor.type("i. one\ntwo\nthree\nfour")
        #expect(editor.markdown == "i. one\nii. two\niii. three\niv. four")
    }

    @Test func typingACapitalIStartsACapitalRomanList() {
        let editor = EditorHarness()
        editor.type("I. one\ntwo")
        #expect(editor.markdown == "I. one\nII. two")
    }

    @Test func fromAChineseKeyboard() {
        let editor = EditorHarness()
        editor.type("a\u{3002} one")
        #expect(editor.markdown == "a. one")
    }

    @Test func otherLettersStayText() {
        let editor = EditorHarness()
        editor.type("P. S. more")
        #expect(editor.textView.text == "P. S. more\n")
    }

    @Test func theItemsShowTheirLetters() {
        let editor = EditorHarness("a. one\nb. two")
        let storage = editor.textView.textStorage
        #expect(storage.attribute(.biteShownStyle, at: 4, effectiveRange: nil) as? String == NumberStyle.letters.rawValue)
        #expect(storage.attribute(.biteOrdinal, at: 4, effectiveRange: nil) as? Int == 2)
    }

    @Test func aNestedListUnderALetteredOneGoesByItsLevel() {
        let editor = EditorHarness()
        editor.type("A. one\n\ttwo")
        #expect(editor.markdown == "A. one\n    1. two")
    }

    /// Leaving a list and starting one in another style right away starts a new list.
    @Test func anotherStyleRightAfterStartsANewList() {
        let editor = EditorHarness()
        editor.type("A. one\ntwo\n\nI. three\nfour")
        #expect(editor.markdown == "A. one\nB. two\nI. three\nII. four")
    }

    /// Digits right after a list carry it on, as numbers after the first do in Markdown.
    @Test func digitsRightAfterCarryOn() {
        let editor = EditorHarness()
        editor.type("a. one\n\n1. two")
        #expect(editor.markdown == "a. one\nb. two")
    }

    @Test func theNumberButtonMakesDigits() {
        let editor = EditorHarness("x")
        editor.moveCaret(line: 0)
        editor.controller.perform(.ordered)
        #expect(editor.markdown == "1. x")
    }

    @Test func partOfAListCopiesAsItLooks() {
        let editor = EditorHarness("a. one\nb. two\nc. three")
        editor.select(from: (1, 0), to: (2, 5))
        editor.controller.copySelection()
        #expect(UIPasteboard.general.string == "b. two\nc. three")
    }

    @Test func pastingALetteredList() {
        let editor = EditorHarness()
        editor.controller.paste("i. x\nii. y")
        #expect(editor.markdown == "i. x\nii. y")
    }

    @Test func backspaceTurnsTheFirstItemIntoText() {
        let editor = EditorHarness("a. one\nb. two")
        editor.moveCaret(line: 0, column: 0)
        editor.backspace()
        #expect(editor.markdown == "one\na. two")
    }

    @Test func undoGivesBackWhatWasTyped() {
        let editor = EditorHarness()
        editor.type("a. ", separateEvents: true)
        editor.undo()
        #expect(editor.textView.text == "a. \n")
    }
}
