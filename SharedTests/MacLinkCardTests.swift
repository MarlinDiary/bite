#if !canImport(UIKit)
import AppKit
import Testing
import BiteKit
@testable import Bite

/// A link is changed in a card floating by it, as on the phone's keys (see the phone's
/// `LinkBarTests`): ⌘K brings it up for the selection, or for the link the caret is in, as do Edit
/// Link in a link's menu and Edit on the pill over a link under the pointer. One at a time, as the
/// panel tests are: which window has the keyboard is the whole app's.
@MainActor
@Suite(.serialized)
struct MacLinkCardTests {
    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteLinkCardTests-\(UUID().uuidString)"))
    }

    /// The panel up, its page holding `markdown` and the keys.
    private func shownPanel(_ markdown: String) -> (panel: PanelController, page: EditorController, card: LinkCard) {
        let store = store()
        let panel = PanelController(store: store, forTesting: true)
        panel.show()
        let page = panel.controllers[store.selection]
        page.load(markdown: markdown)
        page.focus()
        return (panel, page, panel.linkCardForTesting)
    }

    /// ⌘K links the selected text: the card comes up with the text, the keys on the address, the
    /// page showing the link as the address is typed, and Return puts it there, the keys back on
    /// the page. One edit, to undo all at once.
    @Test func commandKLinksTheSelection() {
        let (panel, page, card) = shownPanel("Some words to link")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 5, length: 5))
        page.perform(.link)
        #expect(card.isEditingLink)
        #expect(card.isShown)
        #expect(card.editingLink?.isNew == true)
        #expect(card.nameForTesting == "words")
        #expect(card.addressForTesting == "")
        #expect(card.rowWithKeysForTesting == .address)
        #expect(page.textView.linkTargetForTesting == NSRange(location: 5, length: 5))
        // Typed in the card's own editor, its caret and selection in the page's colours, in either
        // row: a row's cell sets the editor up as the keys come to it.
        #expect(panel.windowForTesting.firstResponder === card.fieldEditor)
        #expect(card.caretColorForTesting == page.textView.insertionPointColor)
        #expect(card.selectionColorForTesting == page.textView.selectionColor)
        card.typeNameForTesting("words")
        #expect(card.caretColorForTesting == page.textView.insertionPointColor)
        #expect(card.selectionColorForTesting == page.textView.selectionColor)
        card.typeAddressForTesting("")
        card.typeAddressForTesting("example.com")
        #expect(page.markdownForTesting == "Some [words](https://example.com) to link")
        #expect(card.namePlaceholderForTesting == "example.com")
        card.returnForTesting()
        #expect(!card.isEditingLink)
        #expect(!card.isShown)
        #expect(panel.windowForTesting.firstResponder === page.textView)
        #expect(page.markdownForTesting == "Some [words](https://example.com) to link")
        page.textView.undoManager?.undo()
        #expect(page.markdownForTesting == "Some words to link")
    }

    /// With the caret in a link, ⌘K brings it up to edit, text and address both, the caret at the
    /// address's end rather than the address selected. Return in the text moves on to the address.
    @Test func theLinkTheCaretIsInComesUpToEdit() {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 6, length: 0))
        page.perform(.link)
        #expect(card.editingLink?.isNew == false)
        #expect(card.nameForTesting == "the site")
        #expect(card.addressForTesting == "https://example.com")
        #expect((panel.windowForTesting.firstResponder as? NSTextView)?.selectedRange() == NSRange(location: 19, length: 0))
        card.typeNameForTesting("a page")
        #expect(card.rowWithKeysForTesting == .name)
        #expect(page.markdownForTesting == "See [a page](https://example.com) now")
        card.returnForTesting()
        #expect(card.rowWithKeysForTesting == .address)
        #expect(card.isEditingLink)
        card.typeAddressForTesting("https://b.c")
        card.returnForTesting()
        #expect(page.markdownForTesting == "See [a page](https://b.c) now")
        #expect(!card.isEditingLink)
    }

    /// Esc puts the link back as it was, whatever was typed, and the keys back on the page, the
    /// caret where it was.
    @Test func escapePutsTheLinkBack() {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 6, length: 0))
        page.perform(.link)
        card.typeNameForTesting("a page")
        card.escapeForTesting()
        #expect(page.markdownForTesting == "See [the site](https://example.com) now")
        #expect(!card.isEditingLink)
        #expect(panel.windowForTesting.firstResponder === page.textView)
        #expect(page.textView.selectedRange() == NSRange(location: 6, length: 0))
        #expect(page.textView.linkTargetForTesting == nil)
    }

    /// The page clicked, or the panel put away, keeps the link as typed, as Done does: it's on the
    /// page already.
    @Test func theKeysGoingElsewhereKeepTheLinkAsTyped() {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 6, length: 0))
        page.perform(.link)
        card.typeAddressForTesting("https://elsewhere.com")
        _ = panel.windowForTesting.makeFirstResponder(page.textView)
        #expect(!card.isEditingLink)
        #expect(page.markdownForTesting == "See [the site](https://elsewhere.com) now")
        #expect(page.textView.linkTargetForTesting == nil)

        page.textView.setSelectedRange(NSRange(location: 6, length: 0))
        page.perform(.link)
        card.typeNameForTesting("a page")
        panel.hide()
        #expect(!card.isEditingLink)
        #expect(page.markdownForTesting == "See [a page](https://elsewhere.com) now")
    }

    /// Text that only says the link's address comes up as the address standing in, in grey, and
    /// follows the address as it's typed.
    @Test func textThatSaysItsAddressStandsInGrey() {
        let (panel, page, card) = shownPanel("Go to www.a.com now")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 8, length: 0))
        page.perform(.link)
        #expect(card.nameForTesting == "")
        #expect(card.namePlaceholderForTesting == "www.a.com")
        // Grey with the keys in either row: drawn vibrant on the glass, a row without them
        // showed its grey in the text's black (user, 2026-10-05).
        #expect(!card.rowsAreVibrantForTesting)
        card.typeAddressForTesting("www.b.com")
        #expect(card.namePlaceholderForTesting == "www.b.com")
        #expect(page.markdownForTesting == "Go to www.b.com now")
        card.returnForTesting()
        #expect(page.markdownForTesting == "Go to www.b.com now")
    }

    /// The card floats by the link, as wide as itself, not the panel: under a link at the top of
    /// the page, where there's no room above, and within the panel.
    @Test func theCardFloatsByTheLink() throws {
        let (panel, page, card) = shownPanel("Some words to link")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 5, length: 5))
        page.perform(.link)
        let drawn = try #require(page.textView.anchorFrame(for: NSRange(location: 5, length: 1)))
        let anchor = try #require(card.superview).convert(drawn, from: page.textView)
        #expect(card.frame.width == LinkCard.width)
        #expect(card.frame.height == LinkCard.height)
        #expect(card.frame.minY >= anchor.maxY)
        #expect(abs(card.frame.minX - (anchor.minX - 10)) < 0.5)
        #expect(try #require(card.superview).bounds.contains(card.frame))
        card.escapeForTesting()
    }

    /// A link right-clicked has a menu of its own: Open Link, Edit Link…, Copy Link and Remove
    /// Link, rows of Bite's own. Other text has Add Link… on top of its own menu.
    @Test func aLinkHasItsOwnMenu() throws {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        let view = page.textView
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let onLink = try #require(view.anchorFrame(for: NSRange(location: 6, length: 1)))
        let window = panel.windowForTesting
        let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: onLink.midX, y: onLink.midY), to: nil),
                                                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                    eventNumber: 0, clickCount: 1, pressure: 1))
        let menu = try #require(view.menu(for: click))
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Open Link", "Edit Link…", "Copy Link", "-", "Remove Link"])
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.view is MenuRow, "\(item.title)")
        }
        func choose(_ title: String) throws {
            let item = try #require(menu.items.first { $0.title == title })
            _ = try #require(item.target as? NSObject).perform(try #require(item.action), with: item)
        }
        var opened: URL?
        page.openURL = { opened = $0 }
        try choose("Open Link")
        #expect(opened == URL(string: "https://example.com"))
        let board = NSPasteboard(name: NSPasteboard.Name("BiteLinkMenuTests"))
        Clipboard.board = board
        defer { Clipboard.board = .general }
        try choose("Copy Link")
        #expect(Clipboard.string == "https://example.com")
        try choose("Edit Link…")
        #expect(card.isEditingLink)
        #expect(card.editingLink?.isNew == false)
        card.escapeForTesting()
        try choose("Remove Link")
        #expect(page.markdownForTesting == "See the site now")

        // Beside a link, the text's own menu, with Add Link… on top, which brings the card up for
        // the selection.
        let offLink = try #require(view.anchorFrame(for: NSRange(location: 1, length: 1)))
        let clickOff = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: view.convert(NSPoint(x: offLink.midX, y: offLink.midY), to: nil),
                                                       modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                       eventNumber: 0, clickCount: 1, pressure: 1))
        let textMenu = try #require(view.menu(for: clickOff))
        #expect(!textMenu.items.contains { $0.title == "Open Link" })
        #expect(textMenu.items.first?.title == "Add Link…")
        #expect(textMenu.items.count > 2)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        let add = try #require(textMenu.items.first)
        #expect(view.validateMenuItem(add))
        _ = try #require(add.target as? NSObject).perform(try #require(add.action), with: add)
        #expect(card.isEditingLink)
        #expect(card.editingLink?.isNew == true)
        #expect(card.nameForTesting == "See")
        card.escapeForTesting()
    }

    /// The pointer coming onto a link brings a pill up under it, with where it goes and Edit, which
    /// brings the card up, the pill gone at once. The pointer leaving takes the pill away at once,
    /// unless it's between the link and the pill, on its way there.
    @Test func aLinkUnderThePointerGetsAPill() throws {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        let bubble = panel.linkBubbleForTesting
        let link = try #require(page.link(at: 6))
        panel.hoverForTesting(link, on: page)
        #expect(bubble.isShown)
        #expect(bubble.addressForTesting == "https://example.com")
        // The address is only said, its text not to be selected or pressed.
        #expect(bubble.addressIsPlainTextForTesting)
        #expect(bubble.editFontForTesting?.fontDescriptor.symbolicTraits.contains(.bold) == false)
        let drawn = try #require(page.textView.anchorFrame(for: link.range))
        let superview = try #require(bubble.superview)
        let anchor = superview.convert(drawn, from: page.textView)
        #expect(bubble.frame.minY >= anchor.maxY)
        // Between the link and the pill, the pill stays.
        let between = superview.convert(NSPoint(x: anchor.minX + 4, y: (anchor.maxY + bubble.frame.minY) / 2), to: nil)
        panel.hoverForTesting(nil, on: page, at: between)
        #expect(bubble.isShown)
        panel.hoverForTesting(nil, on: page)
        #expect(!bubble.isShown)

        panel.hoverForTesting(link, on: page)
        bubble.editForTesting()
        #expect(!bubble.isShown)
        #expect(bubble.isHidden)
        #expect(card.isEditingLink)
        #expect(card.nameForTesting == "the site")
        card.escapeForTesting()
    }

    /// While the card is up, the page behind it takes no clicks or scrolling: a click on it only
    /// puts the card away, the link kept as typed, the caret at its end as after Return.
    @Test func thePageBehindTheCardTakesNoClicks() throws {
        let (panel, page, card) = shownPanel("See [the site](https://example.com) now")
        defer { panel.hide() }
        let shield = panel.linkShieldForTesting
        #expect(shield.isHidden)
        page.textView.setSelectedRange(NSRange(location: 6, length: 0))
        page.perform(.link)
        #expect(!shield.isHidden)
        card.typeAddressForTesting("https://b.c")
        let window = panel.windowForTesting
        let farFromTheCard = NSPoint(x: 20, y: 20)
        #expect(try #require(window.contentView).hitTest(farFromTheCard) === shield)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: farFromTheCard, modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        shield.mouseDown(with: click)
        #expect(!card.isEditingLink)
        #expect(shield.isHidden)
        #expect(page.markdownForTesting == "See [the site](https://b.c) now")
        #expect(window.firstResponder === page.textView)
        #expect(page.textView.selectedRange() == NSRange(location: 12, length: 0))
    }

    /// The Format menu has Link, with ⌘K, lit while a link's text is selected and dimmed where no
    /// link can go, as the phone's button is.
    @Test func theFormatMenuHasLink() throws {
        let format = try #require(MainMenu.make().items.first { $0.title == "Format" }?.submenu)
        let link = try #require(format.items.first { $0.title == "Link" })
        #expect(link.keyEquivalent == "k")
        #expect(link.keyEquivalentModifierMask == .command)
        let (panel, page, _) = shownPanel("Words\n```\ncode\n```")
        defer { panel.hide() }
        page.textView.setSelectedRange(NSRange(location: 0, length: 5))
        #expect(page.textView.validateMenuItem(link))
        #expect(link.state == .off)
        page.textView.setSelectedRange(NSRange(location: 11, length: 0))
        #expect(!page.textView.validateMenuItem(link))

        let (other, linked, _) = shownPanel("See [the site](https://example.com) now")
        defer { other.hide() }
        linked.textView.setSelectedRange(NSRange(location: 4, length: 8))
        #expect(linked.textView.validateMenuItem(link))
        #expect(link.state == .on)
    }
}
#endif
