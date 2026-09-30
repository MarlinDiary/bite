import Testing
@testable import BiteKit

struct InputRulesTests {
    @Test func blockShortcuts() {
        #expect(InputRules.blockShortcut(forPrefix: "#") == .init(.heading1))
        #expect(InputRules.blockShortcut(forPrefix: "###") == .init(.heading3))
        #expect(InputRules.blockShortcut(forPrefix: "-") == .init(.bullet))
        #expect(InputRules.blockShortcut(forPrefix: "12.") == .init(.ordered, number: 12))
        #expect(InputRules.blockShortcut(forPrefix: "3)") == .init(.ordered, number: 3))
        #expect(InputRules.blockShortcut(forPrefix: "####") == .init(.heading4))
        #expect(InputRules.blockShortcut(forPrefix: "######") == .init(.heading6))
        #expect(InputRules.blockShortcut(forPrefix: "#######") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "[]") == .init(.todo))
        #expect(InputRules.blockShortcut(forPrefix: "[x]") == .init(.todo, checked: true))
        #expect(InputRules.blockShortcut(forPrefix: ">") == .init(.quote))
        // Notion's quote marker, straight or as smart quotes type it (U+201C).
        #expect(InputRules.blockShortcut(forPrefix: "\"") == .init(.quote))
        #expect(InputRules.blockShortcut(forPrefix: "\u{201C}") == .init(.quote))
        #expect(InputRules.blockShortcut(forPrefix: "\"a") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "hello") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "#tag") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "1.5") == nil)
        // Letters and Roman numerals, as in Notion; capitals too, as the keyboard types them.
        #expect(InputRules.blockShortcut(forPrefix: "a.") == .init(.ordered, numberStyle: .letters))
        #expect(InputRules.blockShortcut(forPrefix: "A)") == .init(.ordered, numberStyle: .capitalLetters))
        #expect(InputRules.blockShortcut(forPrefix: "i.") == .init(.ordered, numberStyle: .roman))
        #expect(InputRules.blockShortcut(forPrefix: "I\u{3002}") == .init(.ordered, numberStyle: .capitalRoman))
        #expect(InputRules.blockShortcut(forPrefix: "P.") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "ii.") == nil)
    }

    @Test func todoNeedsASpace() {
        #expect(InputRules.blockShortcut(forPrefix: "[]") == .init(.todo))
        #expect(InputRules.blockShortcut(forPrefix: "[ ]") == .init(.todo))
        #expect(InputRules.blockShortcut(forPrefix: "[x]") == .init(.todo, checked: true))
        #expect(InputRules.blockShortcut(forPrefix: "[") == nil)
        #expect(InputRules.blockShortcut(forPrefix: "a[]") == nil)
    }

    @Test func lineShortcuts() {
        #expect(InputRules.lineShortcut(forPrefix: "--", typed: "-") == .divider)
        #expect(InputRules.lineShortcut(forPrefix: "—", typed: "-") == .divider)
        #expect(InputRules.lineShortcut(forPrefix: "``", typed: "`") == .code)
        #expect(InputRules.lineShortcut(forPrefix: "-", typed: "-") == nil)
        #expect(InputRules.closesCodeBlock(prefix: "``", typed: "`"))
        #expect(!InputRules.closesCodeBlock(prefix: "x``", typed: "`"))
    }

    @Test func bold() {
        let match = InputRules.inlineShortcut(prefix: "buy **milk*", typed: "*")
        #expect(match == .init(range: 4..<12, content: 6..<10, style: .bold))
    }

    @Test func italicWaitsForSecondStar() {
        #expect(InputRules.inlineShortcut(prefix: "**bold", typed: "*") == nil)
        #expect(InputRules.inlineShortcut(prefix: "a *italic", typed: "*")?.style == .italic)
    }

    @Test func ignoresSpacedStars() {
        #expect(InputRules.inlineShortcut(prefix: "5 * 3 ", typed: "*") == nil)
        #expect(InputRules.inlineShortcut(prefix: "** ", typed: "*") == nil)
    }

    @Test func codeAndStrikethrough() {
        #expect(InputRules.inlineShortcut(prefix: "run `swift test", typed: "`")?.style == .code)
        #expect(InputRules.inlineShortcut(prefix: "``", typed: "`") == nil)
        #expect(InputRules.inlineShortcut(prefix: "~~gone~", typed: "~")?.style == .strikethrough)
        #expect(InputRules.inlineShortcut(prefix: "~gone", typed: "~") == nil)
    }

    @Test func returnInLists() {
        #expect(InputRules.returnAction(kind: .bullet, indent: 1, lineIsEmpty: true, caretAtStart: true) == .outdent)
        #expect(InputRules.returnAction(kind: .todo, indent: 0, lineIsEmpty: true, caretAtStart: true) == .exitBlock)
        #expect(InputRules.returnAction(kind: .todo, indent: 0, lineIsEmpty: false, caretAtStart: false) == .continueBlock)
        #expect(InputRules.returnAction(kind: .ordered, indent: 0, lineIsEmpty: false, caretAtStart: true) == .itemAbove)
    }

    @Test func returnLeavesHeadingsButNotQuotes() {
        #expect(InputRules.returnAction(kind: .heading1, indent: 0, lineIsEmpty: false, caretAtStart: false) == .splitToParagraph)
        #expect(InputRules.returnAction(kind: .heading1, indent: 0, lineIsEmpty: false, caretAtStart: true) == .paragraphAbove)
        #expect(InputRules.returnAction(kind: .quote, indent: 0, lineIsEmpty: false, caretAtStart: false) == .continueBlock)
        #expect(InputRules.returnAction(kind: .quote, indent: 0, lineIsEmpty: false, caretAtStart: true) == .itemAbove)
        #expect(InputRules.returnAction(kind: .quote, indent: 0, lineIsEmpty: true, caretAtStart: true) == .exitBlock)
        #expect(InputRules.returnAction(kind: .divider, indent: 0, lineIsEmpty: true, caretAtStart: true) == .splitToParagraph)
        #expect(InputRules.returnAction(kind: .paragraph, indent: 0, lineIsEmpty: false, caretAtStart: false) == .insertNewline)
    }

    @Test func returnInCode() {
        #expect(InputRules.returnAction(kind: .code, indent: 0, lineIsEmpty: false, caretAtStart: false) == .continueBlock)
        #expect(InputRules.returnAction(kind: .code, indent: 0, lineIsEmpty: true, caretAtStart: true, nextKind: .code) == .continueBlock)
        #expect(InputRules.returnAction(kind: .code, indent: 0, lineIsEmpty: true, caretAtStart: true, nextKind: .paragraph) == .exitBlock)
        #expect(InputRules.returnAction(kind: .code, indent: 0, lineIsEmpty: true, caretAtStart: true) == .exitBlock)
    }

    @Test func backspaceAtLineStart() {
        #expect(InputRules.backspaceAtLineStart(kind: .bullet, indent: 2) == .outdent)
        #expect(InputRules.backspaceAtLineStart(kind: .todo, indent: 0) == .convertToParagraph)
        #expect(InputRules.backspaceAtLineStart(kind: .paragraph, indent: 0) == .deleteCharacter)
        #expect(InputRules.backspaceAtLineStart(kind: .code, indent: 0, previousKind: .code) == .deleteCharacter)
        #expect(InputRules.backspaceAtLineStart(kind: .code, indent: 0, previousKind: .paragraph) == .convertToParagraph)
        #expect(InputRules.backspaceAtLineStart(kind: .paragraph, indent: 0, previousKind: .divider) == .deleteLineAbove)
        #expect(InputRules.backspaceAtLineStart(kind: .bullet, indent: 0, previousKind: .divider) == .convertToParagraph)
    }

    /// U+300B, U+3010 and U+3011, U+3002, U+FF09, U+00B7 and U+FF5E are what a Chinese keyboard
    /// types for `>`, `[` and `]`, `.`, `)`, a backtick and `~`.
    @Test func chineseKeyboardMarkers() {
        #expect(InputRules.blockShortcut(forPrefix: "\u{300B}") == .init(.quote))
        #expect(InputRules.blockShortcut(forPrefix: "\u{3010}\u{3011}") == .init(.todo))
        #expect(InputRules.blockShortcut(forPrefix: "\u{3010}x\u{3011}") == .init(.todo, checked: true))
        #expect(InputRules.blockShortcut(forPrefix: "2\u{3002}") == .init(.ordered, number: 2))
        #expect(InputRules.blockShortcut(forPrefix: "2\u{FF09}") == .init(.ordered, number: 2))
        #expect(InputRules.blockShortcut(forPrefix: "\u{00B7}") == .init(.bullet))
        #expect(InputRules.blockShortcut(forPrefix: "\u{FF03}\u{FF03}") == .init(.heading2))
        #expect(InputRules.lineShortcut(forPrefix: "\u{00B7}\u{00B7}", typed: "\u{00B7}") == .code)
        #expect(InputRules.closesCodeBlock(prefix: "\u{00B7}\u{00B7}", typed: "\u{00B7}"))
        #expect(InputRules.inlineShortcut(prefix: "\u{FF5E}\u{FF5E}x\u{FF5E}", typed: "\u{FF5E}")?.style == .strikethrough)
        #expect(InputRules.inlineShortcut(prefix: "~~x\u{FF5E}", typed: "\u{FF5E}") == nil)
    }

    @Test func underscores() {
        #expect(InputRules.inlineShortcut(prefix: "a _it", typed: "_")?.style == .italic)
        #expect(InputRules.inlineShortcut(prefix: "__bold_", typed: "_")?.style == .bold)
        #expect(InputRules.inlineShortcut(prefix: "__bold", typed: "_") == nil)
        #expect(InputRules.inlineShortcut(prefix: "snake_case", typed: "_") == nil)
        #expect(InputRules.inlineShortcut(prefix: "_snake_case", typed: "_") == .init(range: 0..<12, content: 1..<11, style: .italic))
        #expect(InputRules.inlineShortcut(prefix: "_ spaced ", typed: "_") == nil)
    }
}
