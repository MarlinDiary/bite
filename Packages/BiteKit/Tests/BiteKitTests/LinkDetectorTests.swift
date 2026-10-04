import Testing
@testable import BiteKit

/// Addresses written out in text, which a page shows as links, and links typed as Markdown.
struct LinkDetectorTests {
    private func addresses(_ text: String) -> [String] {
        let units = Array(text.utf16)
        return LinkDetector.addresses(in: text).map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test func anAddressRunsToTheNextSpace() {
        #expect(addresses("See https://example.com/a?b=1#c and www.apple.com too") == ["https://example.com/a?b=1#c", "www.apple.com"])
        #expect(addresses("HTTP://EXAMPLE.COM") == ["HTTP://EXAMPLE.COM"])
    }

    /// A full stop or comma after it, or a bracket around it, is the sentence's, not the address's.
    @Test func punctuationAfterAnAddressIsNotPartOfIt() {
        #expect(addresses("Go to https://example.com.") == ["https://example.com"])
        #expect(addresses("(see https://example.com/a), then") == ["https://example.com/a"])
        #expect(addresses("https://en.wikipedia.org/wiki/Foo_(bar)") == ["https://en.wikipedia.org/wiki/Foo_(bar)"])
        #expect(addresses("<https://example.com>") == ["https://example.com"])
        #expect(addresses("[see https://example.com/a]") == ["https://example.com/a"])
        #expect(addresses("https://example.com/a[1]") == ["https://example.com/a[1]"])
    }

    /// Text in another script ends an address, and can come right before one.
    @Test func anotherScriptEndsAnAddress() {
        #expect(addresses("\u{770B}https://example.com\u{3002}") == ["https://example.com"])
    }

    /// Past the site's name, words in another script are in an address, as a search's or a page
    /// title's are. Right after the name, or written on at the end of the path, they're not.
    @Test func wordsInAnotherScriptCanBeInAnAddress() {
        let search = "https://m.baidu.com/s?word=Dhdhjsjf\u{4E2D}\u{8D2F}\u{7A7F}\u{5206}&ts=0&t_kt=0&ie=utf-8&rsv_t=1d2cQffp7f%252Fj1yS1QK&sa=ib"
        #expect(addresses(search) == [search])
        #expect(addresses("https://zh.wikipedia.org/wiki/\u{4E2D}\u{6587}") == ["https://zh.wikipedia.org/wiki/\u{4E2D}\u{6587}"])
        #expect(addresses("https://a.com/\u{4E2D}\u{6587}\u{FF0C}\u{7136}\u{540E}") == ["https://a.com/\u{4E2D}\u{6587}"])
        #expect(addresses("www.baidu.com/s?wd=\u{4E2D}\u{6587} then") == ["www.baidu.com/s?wd=\u{4E2D}\u{6587}"])
        // Written on right after the name or the path, they're the sentence's.
        #expect(addresses("\u{8BE6}\u{89C1}https://example.com\u{91CC}\u{7684}") == ["https://example.com"])
        #expect(addresses("\u{8BBF}\u{95EE}https://github.com/foo/bar\u{4E86}\u{89E3}\u{66F4}\u{591A}") == ["https://github.com/foo/bar"])
        #expect(addresses("\u{770B}https://a.com/x\u{4E2D}\u{6587}\u{3002}") == ["https://a.com/x"])
    }

    /// Email addresses are found as GitHub finds them, and go to mail. A full stop after one is
    /// the sentence's, and a domain needs a dot and letters at its end.
    @Test func emailAddressesAreFound() {
        #expect(addresses("Write to me@example.com.") == ["me@example.com"])
        #expect(addresses("a.b+c_d-e@mail.co.uk, or") == ["a.b+c_d-e@mail.co.uk"])
        for none in ["me@localhost", "a@b.c", "@mention", "me@example.c0m", "me@\u{4F8B}.com"] {
            #expect(addresses(none).isEmpty, "\(none)")
        }
        // In a web address it's the web address's.
        #expect(addresses("https://a.b/x@y.com") == ["https://a.b/x@y.com"])
        #expect(LinkDetector.destination(of: "me@example.com") == "mailto:me@example.com")
        #expect(LinkDetector.isAddress(" me@example.com "))
    }

    @Test func halfAnAddressIsNone() {
        for text in ["https://", "www.", "xhttps://a.b", "awww.b.c", "http//a.b", ""] {
            #expect(addresses(text).isEmpty, "\(text)")
        }
    }

    /// A link's address is kept in full: one typed without a scheme is a web address or an email.
    @Test func aTypedAddressIsKeptInFull() {
        #expect(LinkDetector.destination(forTyped: " example.com ") == "https://example.com")
        #expect(LinkDetector.destination(forTyped: "www.apple.com/mac") == "https://www.apple.com/mac")
        #expect(LinkDetector.destination(forTyped: "example.com:8080/a") == "https://example.com:8080/a")
        #expect(LinkDetector.destination(forTyped: "name@example.com") == "mailto:name@example.com")
        for kept in ["https://a.b", "http://a.b", "mailto:a@b.c", "tel:+6421", "obsidian://open?vault=a", "/notes/a.md", "#top", ""] {
            #expect(LinkDetector.destination(forTyped: kept) == kept, "\(kept)")
        }
    }

    @Test func anAddressGoesWhereItSays() {
        #expect(LinkDetector.destination(of: "www.apple.com") == "https://www.apple.com")
        #expect(LinkDetector.destination(of: "http://a.b") == "http://a.b")
        #expect(LinkDetector.isAddress(" https://a.b/c\n"))
        #expect(!LinkDetector.isAddress("see https://a.b"))
    }

    /// Typing the `)` of `[text](address)` makes it a link. An image, a backslash before a
    /// bracket, or an address with a space in it doesn't.
    @Test func aLinkTypedAsMarkdown() {
        #expect(InputRules.linkShortcut(prefix: "See [the site](https://a.b") ==
            InputRules.LinkMatch(range: 4..<27, text: 5..<13, destination: "https://a.b"))
        #expect(InputRules.linkShortcut(prefix: "[a [1] b](u")?.text == 1..<8)
        for prefix in ["![a](b", "\\[a](b", "[a\\](b", "[a](b c", "[a](", "a](b", "[](b"] {
            #expect(InputRules.linkShortcut(prefix: prefix) == nil, "\(prefix)")
        }
    }
}
