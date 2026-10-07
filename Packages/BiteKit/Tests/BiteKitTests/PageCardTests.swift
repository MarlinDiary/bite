import Foundation
import Testing
@testable import BiteKit

/// A page sent in Messages, and read back from the message.
struct PageCardTests {
    @Test func aPageComesBackAsItWasSent() throws {
        let card = PageCard(page: 3, markdown: "# Groceries\n- [ ] Milk\n- [x] Eggs\n\nAsk **Sam** about [the list](https://example.com)")
        let url = try #require(card.url)
        #expect(url.scheme == nil)
        #expect(PageCard(url: url) == card)
    }

    /// Too long for a message, a page loses lines from its end until it fits, and says it did.
    @Test func aLongPageIsCutToFit() throws {
        var generator = SystemRandomNumberGenerator()
        let lines = (0..<2_000).map { _ in String((0..<24).map { _ in "abcdefghijklmnopqrstuvwxyz ".randomElement(using: &generator)! }) }
        let card = PageCard(page: 0, markdown: lines.joined(separator: "\n"))
        let url = try #require(card.url)
        #expect(url.absoluteString.count <= PageCard.room)
        let read = try #require(PageCard(url: url))
        #expect(read.isCut)
        #expect(lines.joined(separator: "\n").hasPrefix(read.markdown))
        #expect(read.markdown.count < card.markdown.count)
    }

    @Test func anotherAddressIsNoCard() throws {
        #expect(PageCard(url: try #require(URL(string: "https://example.com/page?dot=1&text=abc"))) == nil)
        #expect(PageCard(url: try #require(URL(string: "?bite=page&dot=9&text=abc"))) == nil)
        #expect(PageCard(url: try #require(URL(string: "?bite=page&dot=1&text=abc"))) == nil)
    }

    /// What Messages says the message is: the page's first words, or its colour with none.
    @Test func itsTitleIsThePagesFirstWords() {
        #expect(PageCard(page: 2, markdown: "\n\n## Reading list\n- [ ] One").title == "Reading list")
        #expect(PageCard(page: 2, markdown: "").title == DotPalette.colors[2].name)
    }

    /// The bar under the card has the heading the page starts with; a page that starts with
    /// anything else has none, its first line being the page's.
    @Test func itsHeadingIsTheHeadingItStartsWith() {
        #expect(PageCard(page: 0, markdown: "# Groceries\n- [ ] Milk").heading == "Groceries")
        #expect(PageCard(page: 0, markdown: "Milk and eggs\n# Later").heading == nil)
        #expect(PageCard(page: 0, markdown: "").heading == nil)
    }
}
