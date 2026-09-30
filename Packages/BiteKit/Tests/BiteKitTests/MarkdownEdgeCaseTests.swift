import Testing
@testable import BiteKit

private func markdown(_ blocks: [Block]) -> String {
    MarkdownSerializer.markdown(from: BiteDocument(blocks: blocks))
}

private func settles(_ text: String) -> Bool {
    MarkdownSerializer.markdown(from: MarkdownParser.parse(text)) == text
}

struct BlockEdgeCaseTests {
    @Test(arguments: ["--", " --", "- -", "---", "-- --"])
    func bulletOfDashesStaysABullet(_ text: String) {
        let document = BiteDocument(blocks: [Block(.bullet, text)])
        #expect(MarkdownParser.parse(MarkdownSerializer.markdown(from: document)) == document)
    }

    @Test func headingsFourToSix() {
        let text = "#### Four\n##### Five\n###### Six\n####### Seven\n"
        #expect(MarkdownParser.parse(text).blocks.map(\.kind) == [.heading4, .heading5, .heading6, .paragraph])
        #expect(settles(text))
    }

    @Test func orderedListStartsAtItsFirstNumber() {
        let document = MarkdownParser.parse("3. a\n4. b\n9. c\n")
        #expect(document.blocks.map(\.number) == [3, nil, nil])
        #expect(MarkdownSerializer.markdown(from: document) == "3. a\n4. b\n5. c\n")
        #expect(MarkdownParser.parse("1. a\n2. b\n").blocks.map(\.number) == [nil, nil])
        #expect(settles("0. zero\n1. one\n"))
    }

    @Test func eachListAndLevelHasItsOwnStart() {
        #expect(settles("1. a\n    3. x\n    4. y\n2. b\n\n5. new list\n"))
        #expect(settles("- a\n2. b\n"))
    }

    @Test func fenceLanguageIsKept() {
        let document = MarkdownParser.parse("```swift\nlet x = 1\n```\n")
        #expect(document.blocks == [Block(.code, "let x = 1", language: "swift")])
        #expect(MarkdownSerializer.markdown(from: document) == "```swift\nlet x = 1\n```\n")
    }

    @Test func languageWithABacktickGetsTildes() {
        let text = "~~~a`b\ncode\n~~~\n"
        #expect(MarkdownParser.parse(text).blocks == [Block(.code, "code", language: "a`b")])
        #expect(settles(text))
    }

    @Test func tildeFences() {
        #expect(MarkdownParser.parse("~~~\n```\n~~~\n").blocks == [Block(.code, "```")])
        #expect(MarkdownParser.parse("~~~~\n~~~\n~~~~\n").blocks == [Block(.code, "~~~")])
    }

    @Test func fenceInsideCodeGetsALongerFence() {
        #expect(markdown([Block(.code, "```"), Block(.code, "``````")]) == "```````\n```\n``````\n```````\n")
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(MarkdownParser.parse("```\na\n\nb").blocks == [Block(.code, "a"), Block(.code, ""), Block(.code, "b")])
    }

    @Test func emptyFenceIsOneEmptyLine() {
        #expect(MarkdownParser.parse("```\n```\n").blocks == [Block(.code, "")])
    }

    @Test func codeLinesInARowShareAFence() {
        let blocks = [Block(.code, "top"), Block(.code, "a", language: "swift"), Block(.code, "b", language: "python")]
        #expect(markdown(blocks) == "```swift\ntop\na\nb\n```\n")
    }

    @Test func deeperThanItsParentIsPulledUp() {
        // First item indented, a jump of two levels, and an item after a paragraph.
        #expect(markdown([Block(.bullet, "a", indent: 1)]) == "- a\n")
        #expect(markdown([Block(.bullet, "a"), Block(.bullet, "b", indent: 2), Block(.bullet, "c", indent: 1)])
            == "- a\n    - b\n    - c\n")
        #expect(markdown([Block(.paragraph, "p"), Block(.todo, "t", indent: 1)]) == "p\n- [ ] t\n")
        // A subtree keeps its shape.
        #expect(markdown([Block(.ordered, "a", indent: 1), Block(.ordered, "b", indent: 2), Block(.ordered, "c", indent: 1)])
            == "1. a\n    1. b\n2. c\n")
    }

    @Test func lineBreaksOfEveryKind() {
        let document = MarkdownParser.parse("\u{FEFF}# T\r\n- a\r- b\u{2028}c\u{85}d\u{2029}e")
        #expect(document.blocks.map(\.kind) == [.heading1, .bullet, .bullet, .paragraph, .paragraph, .paragraph])
        #expect(document.plainText == "T\na\nb\nc\nd\ne")
    }
}

struct InlineEdgeCaseTests {
    @Test func underscoresFromOtherApps() {
        #expect(InlineParser.parse("_a_ __b__ ___c___") == [
            InlineRun("a", style: .italic), InlineRun(" "), InlineRun("b", style: .bold), InlineRun(" "),
            InlineRun("c", style: [.bold, .italic]),
        ])
        #expect(InlineParser.parse("snake_case_name and __init__") == [
            InlineRun("snake_case_name and "), InlineRun("init", style: .bold),
        ])
        // Underscores between Han characters (U+4E2D, U+6587, U+5B57) are inside a word.
        #expect(InlineParser.parse("\u{4E2D}_\u{6587}_\u{5B57}") == [InlineRun("\u{4E2D}_\u{6587}_\u{5B57}")])
        #expect(InlineParser.parse("*a_") == [InlineRun("*a_")])
    }

    @Test func underscoresInTextStayUnderscores() {
        let runs = [InlineRun("_private, trailing_ snake_case __x__ (_) \u{4E2D}_\u{6587}")]
        let text = MarkdownSerializer.inline(runs)
        #expect(text == "\\_private, trailing\\_ snake_case \\_\\_x\\_\\_ (\\_) \u{4E2D}_\u{6587}")
        #expect(InlineParser.parse(text) == runs)
    }

    @Test func underscoreNextToADelimiter() {
        let runs = [InlineRun("a_", style: .bold), InlineRun("b_c"), InlineRun("_d", style: .italic)]
        #expect(InlineParser.parse(MarkdownSerializer.inline(runs)) == runs)
    }

    @Test(arguments: ["[link](https://example.com)", "![image](a.png)", "<b>html</b>", "| a | b |", "[^1]", "==mark=="])
    func thingsBiteDoesNotStyleStayAsTyped(_ text: String) {
        #expect(MarkdownParser.parse(text).plainText == text)
        #expect(settles(text + "\n"))
    }

    @Test func aBackslashOnItsOwnIsText() {
        #expect(MarkdownParser.parse("a \\ b\\").plainText == "a \\ b\\")
        #expect(settles("a \\\\ b\\\\\n"))
    }
}

struct ListNestingTests {
    @Test func levels() {
        let items: [(kind: BlockKind, indent: Int)] = [
            (.bullet, 1), (.bullet, 3), (.bullet, 2), (.bullet, 1), (.paragraph, 0), (.todo, 2), (.ordered, 0), (.ordered, 5),
        ]
        #expect(ListNesting.levels(for: items) == [0, 1, 1, 0, 0, 0, 0, 1])
    }

    @Test func alreadyValidNestingStays() {
        let items: [(kind: BlockKind, indent: Int)] = [(.bullet, 0), (.bullet, 1), (.bullet, 2), (.bullet, 1), (.bullet, 0)]
        #expect(ListNesting.levels(for: items) == [0, 1, 2, 1, 0])
    }

    @Test func zeroOnlyShowsAsADigit() {
        #expect(ListNumbering.label(for: 0, indent: 0) == "0.")
        #expect(ListNumbering.label(for: 0, indent: 1) == "0.")
        #expect(ListNumbering.label(for: 0, indent: 2) == "0.")
    }
}

/// Lists numbered in letters or Roman numerals, as Notion starts them with `a.` or `i.`.
struct NumberStyleTests {
    @Test func lettersAndRomanNumeralsReadAsLists() {
        let document = MarkdownParser.parse("a. one\nb. two\n\nI. first\nII. second\n\nc) three")
        #expect(document.blocks.map(\.kind) == [.ordered, .ordered, .paragraph, .ordered, .ordered, .paragraph, .ordered])
        #expect(document.blocks.map(\.numberStyle) == [.letters, .letters, nil, .capitalRoman, .capitalRoman, nil, .letters])
        #expect(document.blocks.map(\.number) == [nil, nil, nil, nil, nil, nil, 3])
    }

    @Test func theyWriteBackAsTheyRead() {
        for markdown in ["a. one\nb. two\nc. three\n", "I. first\nII. second\n", "i. x\nii. y\niii. z\niv. w\n", "B. two\nC. three\n"] {
            #expect(MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown)) == markdown)
        }
    }

    @Test func aNestedListKeepsItsOwnStyle() {
        let markdown = "1. top\n    a. letter\n    b. letter\n2. top\n"
        let document = MarkdownParser.parse(markdown)
        #expect(document.blocks.map(\.indent) == [0, 1, 1, 0])
        #expect(MarkdownSerializer.markdown(from: document) == markdown)
    }

    @Test func wordsEndingInADotStayText() {
        for line in ["OK. then", "Hello. there", "ok. sure", "iiii. no", "ic. no", "e.g. this", "Mix. up"] {
            #expect(MarkdownParser.parse(line).blocks.first?.kind == .paragraph, "\(line)")
        }
    }

    /// A paragraph that happens to start like one is escaped.
    @Test func paragraphsThatLookLikeListsAreEscaped() {
        let document = BiteDocument(blocks: [Block(.paragraph, "A. Lincoln"), Block(.paragraph, "iv) four")])
        let markdown = MarkdownSerializer.markdown(from: document)
        #expect(markdown == "A\\. Lincoln\niv\\) four\n")
        #expect(MarkdownParser.parse(markdown) == document)
    }

    /// Letters run out at z, and a lettered list starting at i would read back as Roman.
    @Test func markdownFallsBackToDigits() {
        #expect(ListNumbering.marker(for: 27, style: .letters, startsList: false) == "27.")
        #expect(ListNumbering.marker(for: 9, style: .letters, startsList: true) == "9.")
        #expect(ListNumbering.marker(for: 9, style: .letters, startsList: false) == "i.")
        #expect(ListNumbering.marker(for: 4000, style: .roman, startsList: false) == "4000.")
        // A list past z still reads back lettered: its first item says so.
        let items = (1...28).map { Block(.ordered, "x", numberStyle: $0 == 1 ? .letters : nil) }
        let markdown = MarkdownSerializer.markdown(from: BiteDocument(blocks: items))
        #expect(markdown.hasSuffix("z. x\n27. x\n28. x\n"))
        #expect(MarkdownParser.parse(markdown).blocks.first?.numberStyle == .letters)
    }

    @Test func labels() {
        #expect(ListNumbering.label(for: 3, indent: 0, style: .letters) == "c.")
        #expect(ListNumbering.label(for: 3, indent: 0, style: .capitalLetters) == "C.")
        #expect(ListNumbering.label(for: 4, indent: 1, style: .roman) == "iv.")
        #expect(ListNumbering.label(for: 4, indent: 0, style: .capitalRoman) == "IV.")
        #expect(ListNumbering.label(for: 28, indent: 0, style: .letters) == "ab.")
        // Digits go by level, as before.
        #expect(ListNumbering.label(for: 2, indent: 1) == "b.")
        #expect(ListNumbering.label(for: 2, indent: 2) == "ii.")
    }

    @Test func aListTakesTheStyleOfItsFirstItem() {
        let numbers = ListNumbering.numbers(for: [(.ordered, 0, nil, .roman), (.ordered, 0, nil, nil), (.ordered, 1, nil, nil),
                                                  (.ordered, 0, nil, .letters), (.paragraph, 0, nil, nil), (.ordered, 0, nil, nil)])
        // Items in no style of their own carry on; one in another style starts over.
        #expect(numbers == [.init(ordinal: 1, style: .roman), .init(ordinal: 2, style: .roman), .init(ordinal: 1, style: nil),
                            .init(ordinal: 1, style: .letters), nil, .init(ordinal: 1, style: nil)])
    }
}

/// Where one list ends and the next begins, and markers that could be either kind.
struct NumberStyleBoundaryTests {
    @Test func anotherStyleStartsAnotherList() {
        let document = MarkdownParser.parse("A. one\nB. two\nI. three\nII. four")
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        #expect(numbers.map { $0?.ordinal } == [1, 2, 1, 2])
        #expect(numbers.map { $0?.style } == [.capitalLetters, .capitalLetters, .capitalRoman, .capitalRoman])
    }

    @Test func digitsCarryOnAnyList() {
        let numbers = ListNumbering.numbers(for: [(.ordered, 0, nil, .letters), (.ordered, 0, 7, nil)])
        #expect(numbers == [.init(ordinal: 1, style: .letters), .init(ordinal: 2, style: .letters)])
    }

    @Test func fiveInARomanListIsV() {
        let markdown = "i. a\nii. b\niii. c\niv. d\nv. e\nvi. f\n"
        let document = MarkdownParser.parse(markdown)
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        #expect(numbers.map { $0?.ordinal } == [1, 2, 3, 4, 5, 6])
        #expect(Set(numbers.map { $0?.style }) == [.roman])
        #expect(MarkdownSerializer.markdown(from: document) == markdown)
    }

    @Test func theNinthLetterIsI() {
        let markdown = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"].map { "\($0). x" }.joined(separator: "\n") + "\n"
        let document = MarkdownParser.parse(markdown)
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        #expect(numbers.map { $0?.ordinal } == Array(1...10))
        #expect(Set(numbers.map { $0?.style }) == [.letters])
        #expect(MarkdownSerializer.markdown(from: document) == markdown)
    }

    /// Not every i follows an h: after c it's a new Roman list.
    @Test func anIAfterCStartsARomanList() {
        let document = MarkdownParser.parse("a. x\nb. x\nc. x\ni. y\nii. y")
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        #expect(numbers.map { $0?.ordinal } == [1, 2, 3, 1, 2])
        #expect(numbers.map { $0?.style } == [.letters, .letters, .letters, .roman, .roman])
    }
}
