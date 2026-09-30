import Testing
@testable import BiteKit

private func roundTrip(_ document: BiteDocument) -> BiteDocument {
    MarkdownParser.parse(MarkdownSerializer.markdown(from: document))
}

struct MarkdownRoundTripTests {
    @Test func everyBlockKind() {
        let document = BiteDocument(blocks: [
            Block(.heading1, "Title"),
            Block(.paragraph, "A paragraph"),
            Block(.bullet, "Bullet"),
            Block(.bullet, "Nested", indent: 1),
            Block(.ordered, "First"),
            Block(.ordered, "Second"),
            Block(.todo, "Not done"),
            Block(.todo, "Done", checked: true),
            Block(.quote, "Quote"),
            Block(.code, "let x = 1"),
            Block(.code, ""),
            Block(.code, "print(x)"),
            Block(.divider),
            Block(.paragraph, ""),
            Block(.heading2, "Second level"),
            Block(.heading3, "Third level"),
            Block(.bullet, ""),
            Block(.todo, ""),
            Block(.quote, ""),
            Block(.heading1, ""),
        ])
        #expect(roundTrip(document) == document)
    }

    @Test func readableOutput() {
        let document = BiteDocument(blocks: [
            Block(.heading1, "Weekend"),
            Block(.todo, "Milk"),
            Block(.todo, "Coffee", checked: true),
            Block(.ordered, "One"),
            Block(.ordered, "Two"),
            Block(.bullet, "Child", indent: 1),
        ])
        #expect(MarkdownSerializer.markdown(from: document) == """
        # Weekend
        - [ ] Milk
        - [x] Coffee
        1. One
        2. Two
            - Child

        """)
    }

    @Test func emptyDocument() {
        let document = BiteDocument(blocks: [Block()])
        #expect(roundTrip(document) == document)
        #expect(MarkdownParser.parse("") == document)
    }

    @Test func trailingEmptyParagraphsSurvive() {
        let document = BiteDocument(blocks: [Block(.paragraph, "a"), Block(), Block()])
        #expect(roundTrip(document) == document)
    }

    @Test(arguments: [
        [InlineRun("bold", style: .bold)],
        [InlineRun("a", style: .bold), InlineRun("b", style: [.bold, .italic])],
        [InlineRun("a", style: .italic), InlineRun("b", style: [.bold, .italic])],
        [InlineRun("a", style: [.bold, .italic]), InlineRun("b", style: .italic)],
        [InlineRun("a", style: .bold), InlineRun("b", style: .italic)],
        [InlineRun("a", style: .italic), InlineRun("b", style: .bold)],
        [InlineRun("Note:", style: .bold), InlineRun("here")],
        [InlineRun("(draft)", style: .bold), InlineRun("after")],
        [InlineRun("run "), InlineRun("swift test", style: .code), InlineRun(" to test")],
        [InlineRun("a`b", style: .code)],
        [InlineRun("`x", style: .code)],
        [InlineRun("gone", style: .strikethrough), InlineRun("kept")],
        [InlineRun("5 * 3 = 15, a_b, ~1~, ~~no~~, \\n, `tick`")],
        [InlineRun("hel"), InlineRun("lo", style: .italic)],
        [InlineRun("bold", style: .bold), InlineRun("code", style: [.bold, .code])],
        [InlineRun("a", style: .bold), InlineRun(" "), InlineRun("b", style: .italic)],
    ])
    func inlineRuns(_ runs: [InlineRun]) {
        let document = BiteDocument(blocks: [Block(kind: .paragraph, runs: runs)])
        #expect(roundTrip(document) == document)
    }

    @Test(arguments: [
        "# not a heading", "#", "- not a list", "-", "+ plus", "1. not numbered", "2) paren", "> not a quote",
        "---", "* * *", "___", "*italic* not", "```", "    - indented", "\\ backslash", "[ ] not a to-do",
    ])
    func literalLineStarts(_ text: String) {
        let document = BiteDocument(blocks: [Block(.paragraph, text)])
        #expect(roundTrip(document) == document)
    }

    @Test func bulletThatLooksLikeATask() {
        let document = BiteDocument(blocks: [Block(.bullet, "[ ] literal brackets"), Block(.todo, "[x] also literal")])
        #expect(roundTrip(document) == document)
    }

    @Test func codeContainingFences() {
        let document = BiteDocument(blocks: [Block(.code, "```"), Block(.code, "  ````swift"), Block(.code, "*not* **markdown**")])
        #expect(roundTrip(document) == document)
    }
}

struct MarkdownParserTests {
    @Test func commonVariants() {
        let document = MarkdownParser.parse("""
        ## Title
        * Star bullet
          * Two-space indent
        1) Paren number
        - [X] Capital X
        > Quote
        ***
        Plain **bold** and _underscore_
        """)
        #expect(document.blocks.map(\.kind) == [.heading2, .bullet, .bullet, .ordered, .todo, .quote, .divider, .paragraph])
        #expect(document.blocks[2].indent == 1)
        #expect(document.blocks[4].isChecked)
        #expect(document.blocks[7].runs == [InlineRun("Plain "), InlineRun("bold", style: .bold), InlineRun(" and "),
                                            InlineRun("underscore", style: .italic)])
    }

    @Test func nestedEmphasis() {
        #expect(InlineParser.parse("***both***") == [InlineRun("both", style: [.bold, .italic])])
        #expect(InlineParser.parse("**a*b***") == [InlineRun("a", style: .bold), InlineRun("b", style: [.bold, .italic])])
        #expect(InlineParser.parse("a * b * c") == [InlineRun("a * b * c")])
        #expect(InlineParser.parse("**unclosed") == [InlineRun("**unclosed")])
    }

    @Test func windowsLineEndings() {
        #expect(MarkdownParser.parse("- a\r\n- b\r\n").blocks == [Block(.bullet, "a"), Block(.bullet, "b")])
    }
}

struct ListNumberingTests {
    @Test func restartsAndNests() {
        let ordinals = ListNumbering.ordinals(for: [
            (.ordered, 0), (.ordered, 0), (.ordered, 1), (.ordered, 1), (.ordered, 0),
            (.paragraph, 0), (.ordered, 0), (.bullet, 0), (.ordered, 0),
        ])
        #expect(ordinals == [1, 2, 1, 2, 3, nil, 1, nil, 1])
    }

    @Test func labelsChangeWithEachLevel() {
        #expect(ListNumbering.label(for: 2, indent: 0) == "2.")
        #expect(ListNumbering.label(for: 3, indent: 1) == "c.")
        #expect(ListNumbering.label(for: 4, indent: 2) == "iv.")
        #expect(ListNumbering.label(for: 2, indent: 3) == "2.")
        #expect(ListNumbering.label(for: 1, indent: 4) == "a.")
    }

    @Test func lettersRunPastZ() {
        #expect(ListNumbering.letters(1) == "a")
        #expect(ListNumbering.letters(26) == "z")
        #expect(ListNumbering.letters(27) == "aa")
        #expect(ListNumbering.letters(53) == "ba")
    }

    @Test func romanNumerals() {
        #expect([1, 4, 9, 14, 40, 1994].map { ListNumbering.roman($0) } == ["i", "iv", "ix", "xiv", "xl", "mcmxciv"])
        #expect(ListNumbering.roman(4000) == nil)
        #expect(ListNumbering.label(for: 4000, indent: 2) == "4000.")
    }
}
