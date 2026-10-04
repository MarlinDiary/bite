import Testing
@testable import BiteKit

/// Links, `[text](https://example.com)`, read from Markdown and written back.
struct LinkTests {
    private func runs(_ markdown: String) -> [InlineRun] {
        MarkdownParser.parse(markdown).blocks.first?.runs ?? []
    }

    private func readsBack(_ blocks: [Block]) -> Bool {
        let document = BiteDocument(blocks: blocks)
        return MarkdownParser.parse(MarkdownSerializer.markdown(from: document)) == document
    }

    @Test func aLinkIsItsTextAndWhereItGoes() {
        #expect(runs("See [the site](https://example.com) now") == [
            InlineRun("See "), InlineRun("the site", link: "https://example.com"), InlineRun(" now"),
        ])
    }

    /// A title after the address, as other apps write one, is read and goes: Bite shows it
    /// nowhere. Spaces may stand around the address too. A title left open is no link.
    @Test func aTitleAfterTheAddressGoes() {
        let link = [InlineRun("a", link: "https://x.y")]
        for markdown in [#"[a](https://x.y "The (title)")"#, "[a](https://x.y 'T')", "[a](https://x.y (T))",
                         "[a]( https://x.y )", #"[a](<https://x.y> "T")"#, #"[a](https://x.y "a \" quote")"#] {
            #expect(runs(markdown) == link, "\(markdown)")
        }
        for markdown in [#"[a](https://x.y "T)"#, "[a](https://x.y (a (b)))"] {
            #expect(!runs(markdown).contains { $0.link != nil }, "\(markdown)")
        }
        // Without a space before it, a quote is the address's.
        #expect(runs(#"[a](https://x.y"T")"#) == [InlineRun("a", link: #"https://x.y"T""#)])
    }

    /// Text copied with links in it, as from a web page, gets them written in where their text
    /// is: the second "Apple" here, which is the one linked. A link whose text isn't there is left
    /// out, and the rest is as it was.
    @Test func copiedLinksAreWrittenIn() {
        let text = "Apple makes the Mac. Visit Apple [now]."
        let links: [MarkdownSerializer.CopiedLink] = [("Apple", "https://apple.com", 1), ("gone", "https://x.y", 0), ("Mac*", "https://m.c", 0)]
        #expect(MarkdownSerializer.markdown(of: text, links: links) == "Apple makes the Mac. Visit [Apple](https://apple.com) [now].")
        #expect(MarkdownSerializer.markdown(of: "a *b* c", links: [("*b*", "https://b.c", 0)]) == #"a [\*b\*](https://b.c) c"#)
    }

    /// An address written out but kept from being a link has a backslash where it would start
    /// being one, as GitHub reads it too. It reads back as text with an empty link, and writes
    /// back the same.
    @Test func anAddressKeptFromBeingALink() {
        #expect(runs(#"see www\.a.com now"#) == [InlineRun("see "), InlineRun("www.a.com", link: ""), InlineRun(" now")])
        #expect(runs(#"go https\://a.b/c?d=1."#) == [InlineRun("go "), InlineRun("https://a.b/c?d=1", link: ""), InlineRun(".")])
        #expect(runs(#"**HTTP\://a.b**"#) == [InlineRun("HTTP://a.b", style: .bold, link: "")])
        #expect(runs(#"mail me\@example.com"#) == [InlineRun("mail "), InlineRun("me@example.com", link: "")])
        // Only an address: an escape anywhere else is just text.
        #expect(runs(#"awww\.b.c and http\:"#) == [InlineRun("awww.b.c and http:")])
        for markdown in [#"see www\.a.com now"#, #"go https\://a.b/c?d=1."#, #"**HTTP\://a.b** and [x](https://y.z)"#,
                         #"mail me\@example.com"#] {
            let document = MarkdownParser.parse(markdown)
            #expect(MarkdownSerializer.markdown(from: document) == markdown + "\n", "\(markdown)")
        }
        // As plain text it's the address, with nothing after it.
        #expect(PlainTextSerializer.plainText(from: MarkdownParser.parse(#"see www\.a.com"#)) == "see www.a.com")
    }

    @Test func stylesGoInsideALinkAndAroundIt() {
        #expect(runs("[**bold** and `code`](u)") == [
            InlineRun("bold", style: .bold, link: "u"), InlineRun(" and ", link: "u"), InlineRun("code", style: .code, link: "u"),
        ])
        #expect(runs("**a [b](u) c**") == [
            InlineRun("a ", style: .bold), InlineRun("b", style: .bold, link: "u"), InlineRun(" c", style: .bold),
        ])
    }

    /// Brackets pair up in a link's text and in its address, as in a Wikipedia address. An
    /// address with a space in it is in angle brackets.
    @Test func bracketsPairUp() {
        #expect(runs("[a [1] b](https://en.wikipedia.org/wiki/Foo_(bar))") == [
            InlineRun("a [1] b", link: "https://en.wikipedia.org/wiki/Foo_(bar)"),
        ])
        #expect(runs("[a](<my file.md>)") == [InlineRun("a", link: "my file.md")])
    }

    /// Only a whole link is a link: one with no text or no address, a space before the address,
    /// a space in it, no closing bracket, code around it, or a backslash before a bracket is text.
    @Test func halfALinkIsText() {
        for markdown in ["[](u)", "[a]()", "[a] (u)", "[a](u", "[a](b c)", "`[a](u)`", "\\[a](u)", "[a\\](u)"] {
            #expect(runs(markdown).allSatisfy { $0.link == nil }, "\(markdown)")
        }
        #expect(runs("[a\\](u)").map(\.text).joined() == "[a](u)")
    }

    /// A link can't hold another. The inner one is the link.
    @Test func theInnerOfTwoLinksIsTheLink() {
        #expect(runs("[a [b](u) c](v)") == [InlineRun("[a "), InlineRun("b", link: "u"), InlineRun(" c](v)")])
    }

    @Test func linksAreWrittenAsTheyWereRead() {
        let markdown = "See [the **site**](https://example.com/a_(b)) and [x](<a b>)\n"
        #expect(MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown)) == markdown)
    }

    /// Text that would read as a link, brackets in a link's text and addresses that need angle
    /// brackets or escapes all come back as they were.
    @Test func whatLooksLikeALinkComesBackAsIt() {
        #expect(readsBack([Block(.paragraph, "[x](y) and a]")]))
        #expect(readsBack([Block(kind: .paragraph, runs: [InlineRun("a [b] c]", link: "u"), InlineRun("(d)")])]))
        #expect(readsBack([Block(kind: .paragraph, runs: [InlineRun("[a", style: .italic), InlineRun(" "), InlineRun("](b)", style: .bold)])]))
        for link in ["https://a.b/c d", "x)y", "a(b", "<x>", "a\\b", "a\\)", "https://a.b/(c)"] {
            #expect(readsBack([Block(kind: .bullet, runs: [InlineRun("t", link: link)])]), "\(link)")
        }
    }

    /// An image stays as written, and a link after a `!` of the text's own stays a link.
    @Test func anImageIsNoLink() {
        #expect(runs("![image](a.png)") == [InlineRun("![image](a.png)")])
        #expect(runs("Wow\\![site](u)") == [InlineRun("Wow!"), InlineRun("site", link: "u")])
        #expect(readsBack([Block(kind: .paragraph, runs: [InlineRun("Wow!"), InlineRun("site", link: "u")])]))
    }

    /// Brackets get a backslash only where they'd read back as a link they aren't: pairs in a
    /// link's text, and brackets in text without a parenthesis after them, stay as they are.
    @Test func bracketsAreEscapedOnlyWhenTheyMustBe() {
        for markdown in ["[a [1] b](u)\n", "[^1] and [x] or [y]\n", "- [z] (w)\n"] {
            #expect(MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown)) == markdown, "\(markdown)")
        }
    }

    /// Copied as plain text, a link keeps where it goes, after its text.
    @Test func plainTextSaysWhereALinkGoes() {
        let document = MarkdownParser.parse("[Docs](https://a.b) and [https://c.d](https://c.d)")
        #expect(PlainTextSerializer.plainText(from: document) == "Docs (https://a.b) and https://c.d")
    }
}
