import Testing
@testable import BiteKit

/// A page's words, characters and paragraphs, as the Statistics drawer shows them.
struct PageStatisticsTests {
    private func statistics(_ markdown: String) -> PageStatistics {
        PageStatistics(document: MarkdownParser.parse(markdown))
    }

    /// Only the text counts: not the Markdown, nor what's drawn in front of a line.
    @Test func onlyTheTextCounts() {
        let page = statistics("# Plan\n- **bold** move\n1. first\n- [x] done\n> quoted words\n`code`")
        #expect(page == PageStatistics(words: 8, characters: 38, paragraphs: 6))
    }

    /// Empty lines and dividers hold nothing; the breaks between lines aren't characters.
    @Test func emptyLinesAndDividersAreNotParagraphs() {
        #expect(statistics("one\n\n---\n\ntwo") == PageStatistics(words: 2, characters: 6, paragraphs: 2))
        #expect(statistics("") == PageStatistics())
        #expect(statistics("\n\n") == PageStatistics())
    }

    /// Spaces are characters, but a line of nothing but spaces is no paragraph.
    @Test func spacesAreCharactersButNotWords() {
        #expect(statistics("a  b\n   ") == PageStatistics(words: 2, characters: 7, paragraphs: 1))
    }

    /// Words are told apart as the system tells them: an apostrophe and a number stay in a word,
    /// a dash and punctuation are none, and an emoji is one character.
    @Test func wordsAreToldApartAsTheSystemDoes() {
        #expect(statistics("Don't stop - it's 3.5 km!").words == 5)
        #expect(statistics("\u{1F44B}\u{1F3FD} hi").characters == 4)
    }

    /// Lines of code count as the code block's paragraphs.
    @Test func eachLineOfCodeIsAParagraph() {
        #expect(statistics("```\nlet a = 1\n\nlet b = 2\n```").paragraphs == 2)
    }
}
