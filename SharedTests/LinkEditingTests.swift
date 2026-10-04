#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// Links on a page: shown in the page's colour, kept as text is typed and pasted, and changed
/// or taken off from the link drawer.
@MainActor
struct LinkEditingTests {
    private func isUnderlined(_ location: Int, in editor: EditorHarness) -> Bool {
        (editor.storage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int ?? 0) != 0
    }

    /// A link shows as its text, underlined, and saves as it was written.
    @Test func aLinkShowsAsItsText() throws {
        let editor = EditorHarness("See [the site](https://example.com) now")
        #expect(editor.markdown == "See [the site](https://example.com) now")
        #expect(editor.storage.string.hasPrefix("See the site now"))
        #expect(isUnderlined(4, in: editor))
        #expect(isUnderlined(11, in: editor))
        #expect(!isUnderlined(3, in: editor))
        #expect(!isUnderlined(12, in: editor))
        let link = try #require(editor.controller.link(at: 6))
        #expect(link.range == NSRange(location: 4, length: 8))
        #expect(link.destination == "https://example.com")
        #expect(!link.isWrittenOut)
        #expect(editor.controller.link(at: 13) == nil)
    }

    /// Typing inside a link's text is more of it. Typing on at its end, as after pasting it, isn't.
    @Test func typingInsideALinkIsPartOfIt() {
        let editor = EditorHarness("See [the site](https://example.com) now")
        editor.moveCaret(line: 0, column: 9)
        editor.type("web")
        #expect(editor.markdown == "See [the swebite](https://example.com) now")
        editor.moveCaret(line: 0, column: 15)
        editor.type("s")
        #expect(editor.markdown == "See [the swebite](https://example.com)s now")
        editor.moveCaret(line: 0, column: 4)
        editor.type("a ")
        #expect(editor.markdown == "See a [the swebite](https://example.com)s now")
    }

    /// `[text](address)` typed becomes a link as its `)` is typed, and typing goes on as text.
    @Test func aLinkTypedAsMarkdown() {
        let editor = EditorHarness()
        editor.type("Read [the docs](https://a.b/c)")
        #expect(editor.markdown == "Read [the docs](https://a.b/c)")
        editor.type(" now")
        #expect(editor.markdown == "Read [the docs](https://a.b/c) now")
    }

    /// An address pasted onto text links the text to it. The text stays as it was, styles and all.
    @Test func anAddressPastedOntoTextLinksIt() {
        let editor = EditorHarness("the **best** site")
        editor.select(from: (0, 4), to: (0, 13))
        editor.controller.paste(" https://a.b/c\n")
        #expect(editor.markdown == "the [**best** site](https://a.b/c)")
        // Onto nothing, it's text.
        editor.moveCaret(line: 0)
        editor.controller.paste(" https://d.e")
        #expect(editor.markdown == "the [**best** site](https://a.b/c) https://d.e")
    }

    /// An address written out shows as a link while its Markdown stays plain text, and stops
    /// showing as one when it's typed on into something else. In code it's code.
    @Test func anAddressWrittenOutShowsAsALink() throws {
        let editor = EditorHarness()
        editor.type("Go to https://a.b/c. Then `www.x.y`")
        #expect(editor.markdown == "Go to https://a.b/c. Then `www.x.y`")
        #expect(isUnderlined(6, in: editor))
        #expect(isUnderlined(18, in: editor))
        #expect(!isUnderlined(19, in: editor))
        #expect(!isUnderlined(27, in: editor))
        let link = try #require(editor.controller.link(at: 8))
        #expect(link.isWrittenOut)
        #expect(link.range == NSRange(location: 6, length: 13))
        #expect(link.destination == "https://a.b/c")
        editor.moveCaret(line: 0, column: 6)
        editor.type("x")
        #expect(!isUnderlined(7, in: editor))
        #expect(editor.controller.link(at: 8) == nil)
    }

    /// Loaded, a page's written-out addresses show as links too.
    @Test func aLoadedAddressShowsAsALink() {
        let editor = EditorHarness("see www.apple.com\n- [ ] and https://x.y")
        #expect(isUnderlined(4, in: editor))
        #expect(editor.controller.link(at: 5)?.destination == "https://www.apple.com")
        #expect(editor.controller.link(at: 24)?.destination == "https://x.y")
    }

    /// The drawer changes a link's text and where it goes as one edit, which undo takes back.
    @Test func aLinkChangedAndTakenOff() throws {
        let editor = EditorHarness("See [the site](https://example.com) now")
        let link = try #require(editor.controller.link(at: 6))
        editor.controller.setLink(link, text: "docs", destination: "https://b.c")
        #expect(editor.markdown == "See [docs](https://b.c) now")
        editor.undo()
        #expect(editor.markdown == "See [the site](https://example.com) now")
        editor.controller.setLink(link, text: "the site", destination: " https://c.d ")
        #expect(editor.markdown == "See [the site](https://c.d) now")
        editor.controller.removeLink(try #require(editor.controller.link(at: 6)))
        #expect(editor.markdown == "See the site now")
    }

    /// A link given its own address as text is plain text, which shows as a link anyway. One
    /// shown before the page changed there is left alone.
    @Test func aLinkThatSaysItsAddressIsPlainText() throws {
        let editor = EditorHarness("[a](https://a.b)")
        let link = try #require(editor.controller.link(at: 0))
        editor.controller.setLink(link, text: "https://a.b", destination: "https://a.b")
        #expect(editor.markdown == "https://a.b")
        #expect(isUnderlined(0, in: editor))
        editor.controller.setLink(link, text: "b", destination: "https://c.d")
        #expect(editor.markdown == "https://a.b")
    }

    /// The format bar's link button takes the link off a link's text selected, as bold comes off,
    /// or changes the link the caret is inside, or makes one of the selection, or takes words
    /// selected with a link into it, or puts a new one at the caret. It shows as on only while the
    /// selection is a link's text, as bold does over bold text.
    @Test func theLinkButtonShowsOrMakesALink() throws {
        let editor = EditorHarness("See [the site](https://example.com) now")
        var shown: EditorController.PageLink?
        editor.controller.onEditLink = { shown = $0 }
        editor.select(from: (0, 4), to: (0, 12))
        #expect(editor.controller.isLinkSelected)
        editor.select(from: (0, 5), to: (0, 8))
        #expect(editor.controller.isLinkSelected)
        // Part of a link's text selected comes off it, and the rest stays a link, before and after.
        editor.controller.perform(.link)
        #expect(shown == nil)
        #expect(editor.markdown == "See [t](https://example.com)he [site](https://example.com) now")
        #expect(editor.textView.selectedRange == NSRange(location: 5, length: 3))
        #expect(!editor.controller.isLinkSelected)
        editor.undo()
        // All of it selected, the link goes.
        editor.select(from: (0, 4), to: (0, 12))
        editor.controller.perform(.link)
        #expect(editor.markdown == "See the site now")
        editor.undo()
        #expect(editor.markdown == "See [the site](https://example.com) now")

        // A caret inside a link isn't a selected link, but no new link can go there: the button
        // changes the link it's in, as it isn't at either end.
        editor.moveCaret(line: 0, column: 6)
        #expect(!editor.controller.isLinkSelected)
        shown = nil
        editor.controller.perform(.link)
        #expect(shown?.isNew == false)
        #expect(shown?.destination == "https://example.com")
        // At either end, a new one goes.
        for column in [4, 12] {
            editor.moveCaret(line: 0, column: column)
            #expect(!editor.controller.isLinkSelected)
            shown = nil
            editor.controller.perform(.link)
            #expect(shown?.isNew == true, "caret at \(column)")
        }

        // Selected with part of a link, words join it at once, and the selection stays as it was.
        editor.select(from: (0, 9), to: (0, 16))
        #expect(!editor.controller.isLinkSelected)
        shown = nil
        editor.controller.perform(.link)
        #expect(shown == nil)
        #expect(editor.markdown == "See [the site now](https://example.com)")
        #expect(editor.textView.selectedRange == NSRange(location: 9, length: 7))
        #expect(editor.controller.isLinkSelected)
        editor.undo()
        #expect(editor.markdown == "See [the site](https://example.com) now")

        editor.select(from: (0, 13), to: (0, 16))
        #expect(!editor.controller.isLinkSelected)
        editor.controller.perform(.link)
        let new = try #require(shown)
        #expect(new.isNew)
        #expect(new.text == "now")
        #expect(new.destination.isEmpty)
        editor.controller.setLink(new, text: "now", destination: "https://n.o")
        #expect(editor.markdown == "See [the site](https://example.com) [now](https://n.o)")

        editor.moveCaret(line: 0, column: 3)
        editor.controller.perform(.link)
        let atCaret = try #require(shown)
        #expect(atCaret.isNew && atCaret.text.isEmpty)
        // Right after a letter, an address written out wouldn't show as a link, so it's one.
        editor.controller.setLink(atCaret, text: "", destination: "www.x.y")
        #expect(editor.markdown == "See[www.x.y](https://www.x.y) [the site](https://example.com) [now](https://n.o)")
    }

    /// An address written out comes off as a link from the button, as a link's text does, its text
    /// staying: the Markdown has a backslash where it would start being a link, which GitHub reads
    /// so too. The button puts it back, and an address emptied in the bar takes it off as well.
    @Test func anAddressWrittenOutComesOffAndBack() throws {
        let editor = EditorHarness("Go to www.a.com now")
        editor.select(from: (0, 8), to: (0, 11))
        #expect(editor.controller.isLinkSelected)
        editor.controller.perform(.link)
        #expect(editor.markdown == #"Go to www\.a.com now"#)
        #expect(editor.controller.link(at: 8) == nil)
        #expect(!isUnderlined(8, in: editor))
        #expect(!editor.controller.isLinkSelected)
        // Typed into, it stays text.
        editor.moveCaret(line: 0, column: 10)
        editor.type("x")
        #expect(editor.markdown == #"Go to www\.xa.com now"#)
        #expect(!isUnderlined(8, in: editor))
        editor.select(from: (0, 8), to: (0, 11))
        editor.controller.perform(.link)
        #expect(editor.markdown == "Go to www.xa.com now")
        #expect(isUnderlined(8, in: editor))

        // Edits in one turn of the run loop undo as one, so a page of its own for this.
        let emptied = EditorHarness("Go to www.a.com now")
        let address = try #require(emptied.controller.link(at: 8))
        emptied.controller.setLink(address, text: address.text, destination: "")
        #expect(emptied.markdown == #"Go to www\.a.com now"#)
        emptied.undo()
        #expect(emptied.markdown == "Go to www.a.com now")

        // Loaded so, it's text.
        let loaded = EditorHarness(#"see https\://a.b/c"#)
        #expect(loaded.controller.link(at: 6) == nil)
        #expect(!isUnderlined(6, in: loaded))
    }

    /// Text pasted inside a link's text is more of it, as typed text is. Pasted at its end, or
    /// pasted with links of its own, it isn't.
    @Test func textPastedIntoALinkIsPartOfIt() {
        let editor = EditorHarness("See [the site](https://example.com) now")
        editor.moveCaret(line: 0, column: 8)
        editor.controller.paste("web ")
        #expect(editor.markdown == "See [the web site](https://example.com) now")
        editor.moveCaret(line: 0, column: 16)
        editor.controller.paste("s")
        #expect(editor.markdown == "See [the web site](https://example.com)s now")
        editor.select(from: (0, 4), to: (0, 7))
        editor.controller.paste("[a](https://a.b)")
        #expect(editor.markdown == "See [a](https://a.b)[ web site](https://example.com)s now")
    }

    /// An email address written out shows as a link that mails it, and comes off as one, its
    /// Markdown escaping its `@`.
    @Test func anEmailAddressIsALink() throws {
        let editor = EditorHarness()
        editor.type("Write to me@example.com.")
        #expect(isUnderlined(9, in: editor))
        #expect(!isUnderlined(23, in: editor))
        #expect(editor.controller.link(at: 9)?.destination == "mailto:me@example.com")
        editor.select(from: (0, 9), to: (0, 23))
        editor.controller.perform(.link)
        #expect(editor.markdown == #"Write to me\@example.com."#)
        #expect(!isUnderlined(9, in: editor))
    }

    /// A link coming off text that is an address keeps it from showing as one by its own text.
    @Test func aLinkComingOffAnAddressLeavesItText() {
        let editor = EditorHarness("[www.a.com](https://b.c) and more")
        editor.select(from: (0, 0), to: (0, 9))
        editor.controller.perform(.link)
        #expect(editor.markdown == #"www\.a.com and more"#)
        #expect(!isUnderlined(2, in: editor))
    }

    /// Selected across two links and the words between, all of it becomes the first link. An
    /// address written out, selected with words beside it, becomes a link of them that goes there.
    @Test func wordsTakenIntoTheFirstLink() {
        let editor = EditorHarness("[a](https://a.b) and [c](https://c.d) or visit www.e.f")
        editor.select(from: (0, 0), to: (0, 7))
        editor.controller.perform(.link)
        #expect(editor.markdown == "[a and c](https://a.b) or visit www.e.f")
        editor.select(from: (0, 11), to: (0, 24))
        editor.controller.perform(.link)
        #expect(editor.markdown == "[a and c](https://a.b) or [visit www.e.f](https://www.e.f)")
    }

    /// A link given neither text nor address is nothing: its text goes, in one edit. Given both as
    /// they are, nothing changes, and there's nothing to undo. Text that only says its address is
    /// known as such, so the format bar can let the address stand in for it.
    @Test func aLinkGivenNothingGoes() throws {
        let editor = EditorHarness("See [the site](https://a.b) now, or www.c.d")
        let link = try #require(editor.controller.link(at: 5))
        #expect(!link.saysItsAddress)
        editor.controller.setLink(link, text: link.text, destination: link.address)
        #expect(editor.markdown == "See [the site](https://a.b) now, or www.c.d")
        #expect(editor.textView.undoManager?.canUndo != true)
        editor.controller.setLink(link, text: "", destination: "")
        #expect(editor.markdown == "See  now, or www.c.d")
        editor.undo()
        #expect(editor.markdown == "See [the site](https://a.b) now, or www.c.d")

        let writtenOut = try #require(editor.controller.link(at: 21))
        #expect(writtenOut.saysItsAddress)
        let saysIt = EditorHarness("[c.d](c.d) and [e.f](https://e.f)")
        #expect(try #require(saysIt.controller.link(at: 0)).saysItsAddress)
        #expect(try #require(saysIt.controller.link(at: 8)).saysItsAddress)
    }

    /// An address changed on its own leaves the text as it is, even text that says the old
    /// address: the format bar's two rows are each their own. An address taken away leaves the
    /// text plain.
    @Test func anAddressChangedOnItsOwn() throws {
        let editor = EditorHarness("See [the site](https://a.b) now")
        let link = try #require(editor.controller.link(at: 5))
        editor.controller.setLink(link, text: link.text, destination: " https://x.y ")
        #expect(editor.markdown == "See [the site](https://x.y) now")
        let moved = try #require(editor.controller.link(at: 5))
        editor.controller.setLink(moved, text: moved.text, destination: "")
        #expect(editor.markdown == "See the site now")

        let saysIt = EditorHarness("[c.d](c.d) and www.e.f")
        let named = try #require(saysIt.controller.link(at: 0))
        saysIt.controller.setLink(named, text: named.text, destination: "c.d/e")
        #expect(saysIt.markdown == "[c.d](https://c.d/e) and www.e.f")
        let writtenOut = try #require(saysIt.controller.link(at: 10))
        #expect(writtenOut.address == "www.e.f")
        saysIt.controller.setLink(writtenOut, text: writtenOut.text, destination: "www.g.h")
        #expect(saysIt.markdown == "[c.d](https://c.d/e) and [www.e.f](https://www.g.h)")
    }

    /// A link made in Bite keeps its address in full, for any app reading the Markdown: one typed
    /// without a scheme is a web address, or an email one. To other apps `example.com` alone was a
    /// file beside the page.
    @Test func aLinkMadeInBiteHasItsAddressInFull() throws {
        let editor = EditorHarness()
        editor.type("Read [the docs](example.com) or [mail](me@example.com)")
        #expect(editor.markdown == "Read [the docs](https://example.com) or [mail](mailto:me@example.com)")
        editor.select(from: (0, 0), to: (0, 4))
        editor.controller.paste("www.a.com")
        #expect(editor.markdown.hasPrefix("[Read](https://www.a.com) "))
        // One from elsewhere is kept as it came, and opens all the same.
        let loaded = EditorHarness("[x](example.com)")
        #expect(loaded.markdown == "[x](example.com)")
        #expect(EditorController.PageLink.url(for: "example.com") == URL(string: "https://example.com"))
        #expect(EditorController.PageLink.url(for: "me@example.com") == URL(string: "mailto:me@example.com"))
    }

    /// Text copied with links from a web page or another app pastes with them.
    @Test func linksCopiedAsRichTextPasteAsLinks() throws {
        let rich = NSMutableAttributedString(string: "Visit Apple, or the Mac.")
        rich.addAttribute(.link, value: try #require(URL(string: "https://apple.com")), range: NSRange(location: 6, length: 5))
        let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        #if canImport(UIKit)
        Clipboard.board.items = [["public.utf8-plain-text": rich.string, "public.rtf": rtf]]
        #else
        Clipboard.board.clearContents()
        Clipboard.board.setString(rich.string, forType: .string)
        Clipboard.board.setData(rtf, forType: .rtf)
        #endif
        let editor = EditorHarness()
        editor.textView.paste(nil)
        #expect(editor.markdown == "Visit [Apple](https://apple.com), or the Mac.")

        // A web page's copy, as HTML.
        let html = Data(#"<p>Read <a href="https://example.com/a">the docs</a> first.</p>"#.utf8)
        #if canImport(UIKit)
        Clipboard.board.items = [["public.utf8-plain-text": "Read the docs first.", "public.html": html]]
        #else
        Clipboard.board.clearContents()
        Clipboard.board.setString("Read the docs first.", forType: .string)
        Clipboard.board.setData(html, forType: .html)
        #endif
        let fromWeb = EditorHarness()
        fromWeb.textView.paste(nil)
        #expect(fromWeb.markdown == "Read [the docs](https://example.com/a) first.")
    }

    /// The link button is for a link where there can be one, and says so where there can't.
    @Test func theLinkButtonKnowsWhereALinkCanGo() {
        let editor = EditorHarness("Some text\n```\ncode\n```")
        editor.moveCaret(line: 0, column: 2)
        #expect(editor.controller.canEditLink)
        editor.moveCaret(line: 1, column: 1)
        #expect(!editor.controller.canEditLink)
        editor.select(from: (0, 1), to: (1, 1))
        #expect(!editor.controller.canEditLink)
    }

    /// A page's links, in order, written out or not.
    @Test func aPagesLinksInOrder() {
        let editor = EditorHarness("[a](https://a.b) and www.c.d\n- [e](https://e.f)")
        #expect(editor.controller.links().map(\.destination) == ["https://a.b", "https://www.c.d", "https://e.f"])
    }

    /// Copied, a link is Markdown, and as plain text it says where it goes.
    @Test func aLinkCopiesAsMarkdown() {
        let editor = EditorHarness("See [the site](https://example.com) now")
        editor.select(from: (0, 0), to: (0, 16))
        editor.controller.copySelection()
        #expect(Clipboard.string == "See [the site](https://example.com) now")
    }
}
