import Testing
@testable import BiteKit

/// Copy Plain Text: the page as it shows, without the Markdown.
struct PlainTextTests {
    private func plain(_ blocks: [Block]) -> String {
        PlainTextSerializer.plainText(from: BiteDocument(blocks: blocks))
    }

    @Test func stylesHeadingsAndQuotesAreJustTheirText() {
        let document = MarkdownParser.parse("# Title\n**bold** and *it*, ~~gone~~ `code`\n> quoted\na \\*star\\*")
        #expect(PlainTextSerializer.plainText(from: document) == "Title\nbold and it, gone code\nquoted\na *star*")
    }

    @Test func bulletsGoRoundByLevelAsDrawn() {
        let blocks = [Block(.bullet, "a"), Block(.bullet, "b", indent: 1), Block(.bullet, "c", indent: 2), Block(.bullet, "d", indent: 3)]
        #expect(plain(blocks) == "\u{2022} a\n    \u{25E6} b\n        \u{25AA} c\n            \u{2022} d")
    }

    @Test func numbersReadAsTheyShow() {
        let blocks = [Block(.ordered, "a"), Block(.ordered, "b"), Block(.ordered, "c", indent: 1),
                      Block(.ordered, "d", indent: 2), Block(.ordered, "e")]
        #expect(plain(blocks) == "1. a\n2. b\n    a. c\n        i. d\n3. e")
        #expect(plain([Block(.ordered, "x", number: 3), Block(.ordered, "y")]) == "3. x\n4. y")
        #expect(plain([Block(.ordered, "x", numberStyle: .capitalLetters), Block(.ordered, "y")]) == "A. x\nB. y")
    }

    @Test func toDosGetABox() {
        #expect(plain([Block(.todo, "buy"), Block(.todo, "done", checked: true)]) == "\u{2610} buy\n\u{2611} done")
    }

    @Test func codeKeepsItsLinesAndADividerIsALine() {
        let blocks = [Block(.code, "let x = 1"), Block(.code, "  y"), Block(.divider), Block(.paragraph, "after")]
        #expect(plain(blocks) == "let x = 1\n  y\n\u{2014}\u{2014}\u{2014}\nafter")
    }

    @Test func emptyLinesAtTheEndAreLeftOut() {
        #expect(plain([Block(.paragraph, "a"), Block(.paragraph, ""), Block(.paragraph, "b"), Block(.paragraph, ""), Block(.paragraph, "")]) == "a\n\nb")
        #expect(plain([]) == "")
        #expect(plain([Block(.paragraph, "")]) == "")
    }
}
