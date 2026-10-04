import Testing
import UIKit
import BiteKit
@testable import Bite

/// While a page is being edited with the bar on its keys, a link is changed in the bar: the glass
/// grows a row up from the keys, the link's text above where it goes, and the keys move over to
/// them and back as they are, never going down. A link tapped while typing comes up there; tapped
/// on a page not being edited, it opens (see `LinkTapTests`).
@MainActor
struct LinkBarTests {
    private var bar: FormatBar { FormatBar.shared }

    /// The pages in a window, the first being edited with `markdown` on it, over keys `keys` tall.
    private func editingPager(_ markdown: String, keys: CGFloat = 336) -> (pager: DotPagerCoordinator, page: EditorController, window: UIWindow) {
        let pager = DotPagerCoordinator()
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        EditorHarness.show(window)
        let page = pager.controllers[0]
        page.load(markdown: markdown)
        page.focus()
        pager.container.keysForTesting = keys
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        return (pager, page, window)
    }

    /// Ends a test. A link left open by a failure would carry over into the next test, and the
    /// pager, which nothing else holds, is kept till then: its pages hand their links to it.
    private func finish(_ pager: DotPagerCoordinator) {
        if bar.isEditingLink { bar.editor?.focus() }
        withExtendedLifetime(pager) {}
    }

    /// As a tap on the text in `range` does. Says whether it was taken as a link's.
    private func tap(_ range: NSRange, on page: EditorController) throws -> Bool {
        page.textView.layoutIfNeeded()
        let frame = try #require(page.textView.textFramesForTesting(of: range).first)
        return page.textView.tapLinkForTesting(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// The selected text is linked from the bar, as the link's text. It stays lit while the keys
    /// are on the link, and the bar, grown taller, stays on them, the page making room for it.
    @Test func aSelectionIsLinkedOnTheKeys() {
        let (pager, page, window) = editingPager("Some words to link")
        defer { finish(pager) }
        let room = page.textView.contentInset.bottom
        page.textView.selectedRange = NSRange(location: 5, length: 5)
        page.perform(.link)
        #expect(bar.isEditingLink)
        #expect(bar.showsLinkForTesting)
        #expect(bar.linkTitleForTesting == "Add Link")
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(bar.nameForTesting == "words")
        #expect(bar.addressForTesting == "")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 5, length: 5))
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        let grown = bar.height - FormatBar.height
        #expect(grown > 48)
        #expect(bar.frame.height == bar.height)
        #expect(page.textView.keyboardOverlap == 336 + bar.height)
        #expect(page.textView.contentInset.bottom == room + grown)
        #expect(pager.container.barTrackFrameForTesting.maxY == window.bounds.height - 336)
        #expect(!FormatBar.shared.accessibilityElementsHidden)

        bar.typeAddressForTesting("example.com")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "Some [words](https://example.com) to link")
        #expect(!bar.isEditingLink)
        #expect(!bar.showsLinkForTesting)
        #expect(bar.height == FormatBar.height)
        #expect(page.textView.isFirstResponder)
        #expect(page.textView.linkTargetForTesting == nil)
        #expect(page.textView.keyboardOverlap == 336 + FormatBar.height)
        #expect(page.textView.contentInset.bottom == room)
    }

    /// At the caret, a new link with no text typed for it is its address, which shows in the text's
    /// place as it's typed, and as a link on the page when it's written out.
    @Test func aLinkAtTheCaretIsItsAddress() {
        let (pager, page, _) = editingPager("See ")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 4, length: 0)
        page.perform(.link)
        #expect(bar.isEditingLink)
        #expect(bar.nameForTesting == "")
        #expect(bar.namePlaceholderForTesting == "Text")
        // Where it goes shows on the page, a caret, the page's own having gone with the keys.
        #expect(page.textView.linkTargetForTesting == NSRange(location: 4, length: 0))
        bar.typeAddressForTesting("www.apple.com")
        #expect(bar.namePlaceholderForTesting == "www.apple.com")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See www.apple.com")
        #expect(page.textView.selectedRange == NSRange(location: 17, length: 0))
        #expect(page.textView.isFirstResponder)
    }

    /// At the caret, a new link takes the text typed for it, Return moving on from the text to the
    /// address, the keys staying up and the link still being made.
    @Test func aLinkAtTheCaretTakesTheTextTyped() {
        let (pager, page, _) = editingPager("See ")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 4, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        #expect(bar.rowWithKeysForTesting == .name)
        #expect(bar.isEditingLink)
        bar.typeNameForTesting("Apple")
        bar.returnNameForTesting()
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(bar.isEditingLink)
        bar.typeAddressForTesting("apple.com")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See [Apple](https://apple.com)")
        #expect(page.textView.selectedRange == NSRange(location: 9, length: 0))
        #expect(page.textView.isFirstResponder)
    }

    /// The link the caret is in comes up with the button, its text above where it goes, and both
    /// change together.
    @Test func aLinksTextAndAddressChangeTogether() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        #expect(bar.linkTitleForTesting == "Edit Link")
        #expect(bar.nameForTesting == "the site")
        #expect(bar.addressForTesting == "https://example.com")
        bar.typeNameForTesting("a page")
        bar.typeAddressForTesting("https://b.c")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See [a page](https://b.c) now")
    }

    /// The keys go back to the page from the link, by Done, Return, Cancel or a tap on the page,
    /// with the bar on them all along: it never goes down into them and back up, the page's
    /// room for it with it.
    @Test func theBarStaysOnTheKeysAsTheyGoBackToThePage() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        let ways: [(String, () -> Void)] = [
            ("Done", { self.bar.finishLinkForTesting() }),
            ("Return", { self.bar.returnLinkForTesting() }),
            ("Cancel", { self.bar.cancelLinkForTesting() }),
            ("a tap on the page", { page.focus() }),
        ]
        for (way, giveBack) in ways {
            page.textView.selectedRange = NSRange(location: 6, length: 0)
            page.perform(.link)
            typeName("a page")
            let left = pager.container.timesBarLeftKeysForTesting
            giveBack()
            nextEvent()
            pager.container.setNeedsLayout()
            pager.container.layoutIfNeeded()
            #expect(pager.container.timesBarLeftKeysForTesting == left, "\(way)")
            #expect(!bar.isEditingLink, "\(way)")
            #expect(page.textView.isFirstResponder, "\(way)")
            page.textView.undoManager?.undo()
            nextEvent()
        }
    }

    /// Done puts the link on the page as it stands, from the text as well as from the address,
    /// where Return only moves on.
    @Test func doneFinishesTheLinkFromEitherRow() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        bar.typeNameForTesting("a page")
        bar.finishLinkForTesting()
        #expect(page.markdownForTesting == "See [a page](https://example.com) now")
        #expect(!bar.isEditingLink)
        #expect(page.textView.isFirstResponder)
    }

    /// Cancel gives the page its keys back, the link as it was, whatever was typed for it.
    @Test func cancelLeavesTheLinkAsItWas() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.typeAddressForTesting("https://elsewhere.com")
        bar.cancelLinkForTesting()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")
        #expect(!bar.isEditingLink)
        #expect(!bar.showsLinkForTesting)
        #expect(page.textView.isFirstResponder)
        #expect(page.textView.selectedRange == NSRange(location: 6, length: 0))
    }

    /// As typing in the link's text does, the keys brought there first.
    private func typeName(_ text: String) {
        bar.typeNameForTesting(text)
    }

    /// As typing in the link's address does, the keys brought there first.
    private func typeAddress(_ text: String) {
        bar.typeAddressForTesting(text)
    }

    /// Lets the run loop turn, as it does between keystrokes, so undo steps close.
    private func nextEvent() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
    }

    /// The page shows the link as it's typed in the bar, lit where it is, with nothing to undo
    /// meanwhile. Cancel puts it back as it was, and the caret too.
    @Test func thePageShowsTheLinkAsItsTyped() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("a page")
        nextEvent()
        #expect(page.markdownForTesting == "See [a page](https://example.com) now")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 4, length: 6))
        bar.tapAddressForTesting()
        typeAddress("b.c")
        nextEvent()
        #expect(page.markdownForTesting == "See [a page](https://b.c) now")
        // An address emptied shows the link coming off.
        typeAddress("")
        #expect(page.markdownForTesting == "See a page now")
        #expect(page.textView.undoManager?.canUndo != true)

        bar.cancelLinkForTesting()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")
        #expect(page.textView.selectedRange == NSRange(location: 6, length: 0))
        #expect(page.textView.undoManager?.canUndo != true)
    }

    /// Done makes the link as it was typed one edit, undone all at once. With nothing typed it
    /// makes none, and leaves nothing to undo.
    @Test func doneIsOneStepToUndo() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.textView.undoManager?.canUndo != true)
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        for typed in ["a", "a p", "a page"] {
            typeName(typed)
            nextEvent()
        }
        bar.tapAddressForTesting()
        typeAddress("b.c")
        nextEvent()
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.markdownForTesting == "See [a page](https://b.c) now")
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")
        #expect(page.textView.undoManager?.canUndo != true)
    }

    /// A new link at the caret shows as its address is typed, and goes again if it's cancelled.
    @Test func aNewLinkShowsAsItsAddressIsTyped() {
        let (pager, page, _) = editingPager("See ")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 4, length: 0)
        page.perform(.link)
        typeAddress("apple.com")
        #expect(page.markdownForTesting == "See [apple.com](https://apple.com)")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 4, length: 9))
        bar.cancelLinkForTesting()
        #expect(page.markdownForTesting == "See ")
    }

    /// Text that only says the link's address isn't text that was typed: it comes up as the
    /// address standing in, in grey, and follows the address as it's typed, on the page too. Text
    /// typed stays as typed, whatever the address does.
    @Test func textThatSaysItsAddressStandsInGreyAndFollowsIt() {
        let (pager, page, _) = editingPager("Go to www.a.com or [apple.com](https://apple.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 8, length: 0)
        page.perform(.link)
        #expect(bar.nameForTesting == "")
        typeAddress("www.b.com")
        #expect(bar.nameForTesting == "")
        #expect(bar.namePlaceholderForTesting == "www.b.com")
        #expect(page.markdownForTesting == "Go to www.b.com or [apple.com](https://apple.com) now")
        typeName("Apple")
        #expect(page.markdownForTesting == "Go to [Apple](https://www.b.com) or [apple.com](https://apple.com) now")
        typeAddress("www.c.com")
        #expect(bar.nameForTesting == "Apple")
        bar.finishLinkForTesting()
        #expect(page.markdownForTesting == "Go to [Apple](https://www.c.com) or [apple.com](https://apple.com) now")

        // A link made from its address alone comes up so again, as it was typed, and left so
        // changes nothing.
        page.textView.selectedRange = NSRange(location: 20, length: 0)
        page.perform(.link)
        #expect(bar.nameForTesting == "")
        #expect(bar.namePlaceholderForTesting == "apple.com")
        #expect(bar.addressForTesting == "apple.com")
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.markdownForTesting == "Go to [Apple](https://www.c.com) or [apple.com](https://apple.com) now")
        // No edit of its own: undo takes back the change before it.
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "Go to www.a.com or [apple.com](https://apple.com) now")
    }

    /// Both rows emptied is nothing: the link's text goes from the page, as it shows, Done keeping
    /// that as one edit, and Cancel putting it back. Text standing in for an address goes with
    /// the address.
    @Test func bothRowsEmptiedTakeTheLinksTextAway() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        typeAddress("")
        #expect(page.markdownForTesting == "See the site now")
        bar.tapNameForTesting()
        typeName("")
        #expect(page.markdownForTesting == "See  now")
        bar.cancelLinkForTesting()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")

        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("")
        typeAddress("")
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.markdownForTesting == "See  now")
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")

        let (other, address, _) = editingPager("Go to www.a.com now")
        defer { finish(other) }
        address.textView.selectedRange = NSRange(location: 8, length: 0)
        address.perform(.link)
        typeAddress("www.a")
        #expect(address.markdownForTesting == "Go to www.a now")
        typeAddress("")
        #expect(address.markdownForTesting == "Go to  now")
        bar.cancelLinkForTesting()
        #expect(address.markdownForTesting == "Go to www.a.com now")
    }

    /// Another link tapped while one is shown as it's typed: that one is kept as typed, and the
    /// one tapped comes up where it is then.
    @Test func anotherLinkTappedKeepsTheFirstAsTyped() throws {
        let (pager, page, _) = editingPager("See [the site](https://example.com) and [more](https://b.c)")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("x")
        #expect(page.markdownForTesting == "See [x](https://example.com) and [more](https://b.c)")
        // Its own text, tapped, is the link already being changed.
        #expect(try tap(NSRange(location: 4, length: 1), on: page))
        #expect(bar.nameForTesting == "x")
        #expect(try tap(NSRange(location: 10, length: 4), on: page))
        #expect(page.markdownForTesting == "See [x](https://example.com) and [more](https://b.c)")
        #expect(bar.nameForTesting == "more")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 10, length: 4))
        typeName("most")
        bar.finishLinkForTesting()
        #expect(page.markdownForTesting == "See [x](https://example.com) and [most](https://b.c)")
    }

    /// A new link with no address is its text, as text, as the page showed it: kept when another
    /// link is tapped, which comes up where it is then.
    @Test func aNewLinkWithNoAddressIsItsTextWhenAnotherIsTapped() throws {
        let (pager, page, _) = editingPager("See [more](https://b.c)")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 0, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("Apple ")
        #expect(page.markdownForTesting == "Apple See [more](https://b.c)")
        #expect(try tap(NSRange(location: 10, length: 4), on: page))
        #expect(page.markdownForTesting == "Apple See [more](https://b.c)")
        #expect(bar.nameForTesting == "more")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 10, length: 4))
    }

    /// A new link given no address makes no link, and what the page showed stays: its text, as
    /// text, which shows as a link by its own text if it's an address. Nothing typed, nothing
    /// changes, and there's nothing to undo. Text emptied with no address to stand for it is
    /// nothing, as it shows.
    @Test func aNewLinkWithNoAddressIsItsText() {
        let (pager, page, _) = editingPager("A one b [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 2, length: 3)
        page.perform(.link)
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.markdownForTesting == "A one b [the site](https://example.com) now")
        #expect(page.textView.undoManager?.canUndo != true)

        page.textView.selectedRange = NSRange(location: 2, length: 3)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("")
        #expect(page.markdownForTesting == "A  b [the site](https://example.com) now")
        typeName("two")
        #expect(page.markdownForTesting == "A two b [the site](https://example.com) now")
        bar.finishLinkForTesting()
        nextEvent()
        #expect(page.markdownForTesting == "A two b [the site](https://example.com) now")
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "A one b [the site](https://example.com) now")

        // An address typed as the text, with none to go to, is text, and a link by its own text.
        page.textView.selectedRange = NSRange(location: 0, length: 0)
        page.perform(.link)
        bar.tapNameForTesting()
        typeName("www.b.com ")
        #expect(page.markdownForTesting == "www.b.com A one b [the site](https://example.com) now")
        #expect(page.link(at: 2)?.isWrittenOut == true)
        bar.finishLinkForTesting()
        #expect(page.markdownForTesting == "www.b.com A one b [the site](https://example.com) now")
    }

    /// The link's text is typed as it is, a link being mostly mid-sentence: nothing capitalised.
    @Test func theLinksTextIsNotCapitalised() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        #expect(bar.fieldForTesting.autocapitalizationType == .none)
    }

    /// Text emptied is the address, and an address written out where it would show as a link is
    /// one with no Markdown around it.
    @Test func textEmptiedIsTheAddress() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.typeNameForTesting("")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See https://example.com now")
    }

    /// A link whose address is emptied comes off, its text staying as it was.
    @Test func aLinkComesOffOnTheKeys() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        #expect(bar.isEditingLink)
        bar.typeAddressForTesting("")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See the site now")
        #expect(!bar.isEditingLink)
        #expect(page.textView.isFirstResponder)
    }

    /// An address written out comes up as its address, the text row empty with the address
    /// standing in, and changes as written: an address written out again.
    @Test func anAddressWrittenOutChangesAsWritten() {
        let (pager, page, _) = editingPager("Go to www.a.com now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 8, length: 0)
        page.perform(.link)
        #expect(bar.nameForTesting == "")
        #expect(bar.namePlaceholderForTesting == "www.a.com")
        #expect(bar.addressForTesting == "www.a.com")
        typeAddress("www.b.com")
        #expect(bar.namePlaceholderForTesting == "www.b.com")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "Go to www.b.com now")
    }

    /// While typing, a tap on a link's text brings it up in the bar, and nothing opens. The caret
    /// stays where it was. Tapped again, the link keeps what's been typed for it; another link
    /// tapped comes up in its place.
    @Test func aLinkTappedWhileTypingComesUpInTheBar() throws {
        let (pager, page, _) = editingPager("See [the site](https://example.com) and [more](https://b.c)")
        defer { finish(pager) }
        var opened: URL?
        page.openURL = { opened = $0 }
        page.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(try tap(NSRange(location: 4, length: 8), on: page))
        #expect(opened == nil)
        #expect(bar.isEditingLink)
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(bar.nameForTesting == "the site")
        #expect(bar.addressForTesting == "https://example.com")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 4, length: 8))
        #expect(page.textView.selectedRange == NSRange(location: 2, length: 0))

        bar.typeAddressForTesting("https://typed.com")
        #expect(try tap(NSRange(location: 4, length: 8), on: page))
        #expect(bar.addressForTesting == "https://typed.com")

        // Another link tapped: the first is kept as typed, and the other comes up.
        #expect(try tap(NSRange(location: 17, length: 4), on: page))
        #expect(page.markdownForTesting == "See [the site](https://typed.com) and [more](https://b.c)")
        #expect(bar.nameForTesting == "more")
        #expect(bar.addressForTesting == "https://b.c")
        #expect(page.textView.linkTargetForTesting == NSRange(location: 17, length: 4))
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See [the site](https://typed.com) and [more](https://b.c)")
        #expect(opened == nil)
    }

    /// A link one letter long comes up as any other, tapped while typing.
    @Test func aOneLetterLinkComesUpWhenTapped() throws {
        let (pager, page, _) = editingPager("A [b](https://x.y) c")
        defer { finish(pager) }
        #expect(try tap(NSRange(location: 2, length: 1), on: page))
        #expect(bar.nameForTesting == "b")
        #expect(bar.addressForTesting == "https://x.y")
        bar.typeNameForTesting("bee")
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "A [bee](https://x.y) c")
    }

    /// Moving between the link's text and its address, by a tap or by Return, the link is still
    /// being changed, and what was typed in either stays.
    @Test func theKeysMoveBetweenTheLinksRows() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        bar.typeAddressForTesting("https://b.c")
        bar.tapNameForTesting()
        #expect(bar.rowWithKeysForTesting == .name)
        #expect(bar.isEditingLink)
        #expect(bar.showsLinkForTesting)
        bar.typeNameForTesting("a page")
        bar.tapAddressForTesting()
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(bar.isEditingLink)
        bar.tapNameForTesting()
        bar.returnNameForTesting()
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(bar.isEditingLink)
        // The text as typed, lit on the page.
        #expect(page.textView.linkTargetForTesting == NSRange(location: 4, length: 6))
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "See [a page](https://b.c) now")
    }

    /// The page taking the keys back, as a tap on it does, keeps the link as typed, as Done does:
    /// it's on the page already. Only Cancel puts it back as it was.
    /// The rows are two lines of one text, the keys on whichever line the caret is on: moving
    /// between them only moves the caret, nothing the keys are rebuilt for. Neither line takes the
    /// other in, lines pasted go in as one, and an address that wraps makes its row, and the bar,
    /// taller.
    /// Where the line at `offset` in the rows' text starts, from the text's top.
    private func lineTop(at offset: Int) -> CGFloat {
        let field = bar.fieldForTesting
        return field.caretRect(for: field.position(from: field.beginningOfDocument, offset: offset)!).minY
    }

    /// The rows stand a row apart whether or not there's text on them: a line left empty is as
    /// tall as one with text, and as far from the other row.
    @Test func emptyRowsStandARowApart() {
        let (pager, page, _) = editingPager("Some words to link")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 5, length: 0)
        page.perform(.link)
        #expect(bar.fieldForTesting.text == "\n")
        #expect(bar.rowWithKeysForTesting == .address)
        let top = lineTop(at: 0)
        #expect(lineTop(at: 1) - top == 48, "typing \(String(describing: bar.fieldForTesting.typingAttributes[.paragraphStyle])) text \(bar.fieldForTesting.attributedText!)")
        #expect(bar.rowsHeightForTesting == 96)
        bar.typeAddressForTesting("b.c")
        #expect(lineTop(at: 1) - top == 48)
        bar.tapNameForTesting()
        #expect(lineTop(at: 1) - top == 48)
        bar.typeNameForTesting("words")
        #expect(lineTop(at: 6) - top == 48)
        bar.typeAddressForTesting("")
        #expect(lineTop(at: 6) - top == 48)
        #expect(bar.rowsHeightForTesting == 96)
        bar.cancelLinkForTesting()
    }

    @Test func theRowsAreTwoLinesOfOneText() {
        let (pager, page, _) = editingPager("Some words to link")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 5, length: 5)
        page.perform(.link)
        let field = bar.fieldForTesting
        #expect(field.text == "words\n")
        #expect(bar.rowsHeightForTesting == 96, "\(bar.rowsHeightForTesting)")
        #expect(bar.caretForTesting == 6)
        // The rows meet halfway between their lines: a tap in the gap under the text row's text
        // is the text row's, on the row's line where it's tapped, and one over the address's is
        // the address's, with the text itself taking taps on it.
        #expect(bar.tapRowsForTesting(at: CGPoint(x: 100, y: 42)))
        #expect(bar.rowWithKeysForTesting == .name)
        #expect(bar.caretForTesting == 5)
        #expect(bar.tapRowsForTesting(at: CGPoint(x: 60, y: 42)))
        #expect(bar.caretForTesting < 5)
        #expect(bar.tapRowsForTesting(at: CGPoint(x: 100, y: 54)))
        #expect(bar.rowWithKeysForTesting == .address)
        #expect(!bar.tapRowsForTesting(at: CGPoint(x: 60, y: 24)))
        bar.tapNameForTesting()
        #expect(bar.caretForTesting == bar.separatorForTesting)
        #expect(bar.rowWithKeysForTesting == .name)
        // Backspace at the start of the address, and a selection across the rows, can't take the
        // break between them.
        #expect(!bar.textView(field, shouldChangeTextIn: NSRange(location: 5, length: 1), replacementText: ""))
        field.selectedRange = NSRange(location: 2, length: 4)
        #expect(field.selectedRange == NSRange(location: 2, length: 0))
        bar.tapAddressForTesting()
        bar.pasteForTesting("https://example.com/a\nb")
        #expect(bar.addressForTesting == "https://example.com/a b")
        #expect(bar.nameForTesting == "words")
        #expect(field.text == "words\nhttps://example.com/a b")

        bar.typeAddressForTesting(String(repeating: "https://example.com/", count: 4))
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        #expect(bar.rowsHeightForTesting > 96)
        #expect(bar.height == FormatBar.height - 48 + 44 + bar.rowsHeightForTesting)
        #expect(bar.frame.height == bar.height)
        bar.typeAddressForTesting("b.c")
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        #expect(bar.rowsHeightForTesting == 96, "\(bar.rowsHeightForTesting)")
        #expect(bar.frame.height == bar.height)
        bar.returnLinkForTesting()
        #expect(page.markdownForTesting == "Some [words](https://b.c) to link")
    }

    @Test func thePageTakingTheKeysKeepsTheLinkAsTyped() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        typeAddress("https://elsewhere.com")
        bar.tapNameForTesting()
        typeName("elsewhere")
        page.focus()
        #expect(page.markdownForTesting == "See [elsewhere](https://elsewhere.com) now")
        #expect(!bar.isEditingLink)
        #expect(!bar.showsLinkForTesting)
        #expect(page.textView.isFirstResponder)
        #expect(page.textView.linkTargetForTesting == nil)
        // One edit, to undo all at once.
        nextEvent()
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")
    }

    /// Another page taking the keys, from the dot bar or a swipe, keeps the link as typed.
    @Test func anotherPageTakingTheKeysKeepsTheLinkAsTyped() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        typeAddress("https://elsewhere.com")
        pager.show(page: 1)
        #expect(pager.controllers[1].textView.isFirstResponder)
        #expect(!bar.isEditingLink)
        #expect(page.markdownForTesting == "See [the site](https://elsewhere.com) now")
        #expect(page.textView.linkTargetForTesting == nil)
    }

    /// Words selected with a link, or part of one, join it at once when the button is pressed:
    /// nothing to type, and the link's text beyond the selection stays in it. The selection stays
    /// as it was made, now all link, the button on. Pressed again, it takes the link off what's
    /// selected, as bold would. Typing on at a link's end leaves the link as it was, so this is
    /// how it takes in words.
    @Test func wordsSelectedWithALinkJoinIt() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 9, length: 7)
        page.perform(.link)
        #expect(page.markdownForTesting == "See [the site now](https://example.com)")
        #expect(page.textView.selectedRange == NSRange(location: 9, length: 7))
        #expect(!bar.isEditingLink)
        #expect(bar.showsOn(.link))
        page.perform(.link)
        #expect(page.markdownForTesting == "See [the s](https://example.com)ite now")
        #expect(!bar.showsOn(.link))
        #expect(!bar.isEditingLink)
    }

    /// The link button dims where no link can go, as in code.
    @Test func theLinkButtonDimsWhereNoLinkCanGo() {
        let (pager, page, _) = editingPager("Words\n```\ncode\n```")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(bar.isEnabled(.link))
        page.textView.selectedRange = NSRange(location: 11, length: 0)
        #expect(!bar.isEnabled(.link))
    }

    /// With no keys on screen, as with a hardware keyboard, there's no bar to change a link in,
    /// and a tap on a link's text is a tap on text.
    @Test func withNoKeysThereIsNoLinkToChange() throws {
        let (pager, page, _) = editingPager("Some words to link [here](https://a.b)", keys: 0)
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 5, length: 5)
        page.perform(.link)
        #expect(!bar.isEditingLink)
        #expect(page.textView.isFirstResponder)
        #expect(try !tap(NSRange(location: 19, length: 4), on: page))
        #expect(!bar.isEditingLink)
    }

    /// The caret in a link leaves the bar as it is, its buttons in reach: typing goes on in the
    /// link's text.
    @Test func theCaretInALinkLeavesTheButtons() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        #expect(!bar.showsLinkForTesting)
        #expect(!bar.isEditingLink)
        #expect(bar.height == FormatBar.height)
        page.textView.insertText("o")
        #expect(page.markdownForTesting == "See [thoe site](https://example.com) now")
    }

    /// The button putting the keys away gives way to a link's rows, with the other buttons, and
    /// comes back with them. Keys put away otherwise, swiped down, keep the link as typed.
    @Test func theButtonPuttingTheKeysAwayGivesWayToALink() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        #expect(bar.showsPutKeysAwayForTesting)
        page.textView.selectedRange = NSRange(location: 6, length: 0)
        page.perform(.link)
        #expect(!bar.showsPutKeysAwayForTesting)
        typeAddress("https://elsewhere.com")
        bar.resignLinkForTesting()
        #expect(!bar.isEditingLink)
        #expect(!page.textView.isFirstResponder)
        #expect(bar.showsPutKeysAwayForTesting)
        #expect(page.markdownForTesting == "See [the site](https://elsewhere.com) now")
    }

    /// The link button shows as on only while a link's text is selected.
    @Test func theLinkButtonIsOnOnlyForASelectedLink() {
        let (pager, page, _) = editingPager("See [the site](https://example.com) now")
        defer { finish(pager) }
        for caret in [4, 6, 12] {
            page.textView.selectedRange = NSRange(location: caret, length: 0)
            #expect(!bar.showsOn(.link), "caret at \(caret)")
        }
        page.textView.selectedRange = NSRange(location: 4, length: 8)
        #expect(bar.showsOn(.link))
        page.textView.selectedRange = NSRange(location: 9, length: 7)
        #expect(!bar.showsOn(.link))
    }
}
