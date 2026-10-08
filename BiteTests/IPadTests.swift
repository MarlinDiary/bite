import Testing
import SwiftUI
import UIKit
import BiteKit
@testable import Bite

/// Bite on an iPad: lines kept to a readable length, as on a Mac; no format bar on the keys, as in
/// Notes, the styles being in the system's format panel out of Aa at the top, and links added and
/// changed from the menu over the text, in a card in the middle of the screen.
@MainActor @Suite(.serialized)
struct IPadTests {
    /// A window as wide as a 13-inch iPad upright, as an iPad's, or a phone's.
    private func window(isPad: Bool) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        window.traitOverrides.userInterfaceIdiom = isPad ? .pad : .phone
        return window
    }

    /// The text stops at Notion's measure, 44 of its ems, in the middle of a wide window, as on a
    /// Mac: a wider window only widens the margins. A phone's keeps its margins, however wide.
    @Test func theTextStopsAtAReadableLength() {
        for isPad in [true, false] {
            let window = window(isPad: isPad)
            let page = EditorController(dot: 0, accent: .systemOrange)
            page.load(markdown: "A line long enough to run across the whole of a wide window, were nothing to stop it.")
            page.textView.frame = window.bounds
            window.addSubview(page.textView)
            EditorHarness.show(window)
            page.textView.setNeedsLayout()
            page.textView.layoutIfNeeded()
            let insets = page.textView.textContainerInset
            if isPad {
                #expect(abs(insets.left - (1032 - BiteTextView.widestText) / 2) < 0.5)
                #expect(abs(insets.right - insets.left) < 0.5)
                #expect(BiteTextView.widestText == 748)
            } else {
                #expect(insets.left == BiteTextView.sideMargin)
            }
            window.isHidden = true
        }
    }

    /// The pages in a window, the first being typed in on keys 400 points tall.
    private func editingPager(isPad: Bool, markdown: String = "Some words to style") -> (pager: DotPagerCoordinator, page: EditorController, window: UIWindow) {
        let pager = DotPagerCoordinator()
        let window = window(isPad: isPad)
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        EditorHarness.show(window)
        let page = pager.controllers[0]
        page.load(markdown: markdown)
        page.focus()
        pager.container.keysForTesting = 400
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        return (pager, page, window)
    }

    /// No bar comes up on an iPad's keys, as in Notes: the page makes room for the keys alone. A
    /// phone's keys carry the bar as ever.
    @Test func noBarComesUpOnAnIPadsKeys() {
        for isPad in [true, false] {
            let (pager, page, window) = editingPager(isPad: isPad)
            withExtendedLifetime(pager) {
                #expect(FormatBar.shared.accessibilityElementsHidden == isPad)
                #expect(page.textView.keyboardOverlap == 400 + (isPad ? 0 : FormatBar.height))
            }
            page.textView.resignFirstResponder()
            window.isHidden = true
        }
    }

    /// In a narrow window Aa goes, rather than press up against the dots: past the system's window
    /// controls it needs 470 points (user, 2026-10-09). Full screen, maximized, on a phone or in the
    /// share extension the button at the bar's start stays.
    @Test func aaGoesInANarrowWindow() {
        #expect(TopBarPlacement.startButtonFits(width: 1376, side: 20, windowControls: 0))
        #expect(TopBarPlacement.startButtonFits(width: 1032, side: 20, windowControls: 9))
        #expect(TopBarPlacement.startButtonFits(width: 375, side: 16, windowControls: 0))
        #expect(!TopBarPlacement.startButtonFits(width: 375, side: 20, windowControls: 66))
        #expect(!TopBarPlacement.startButtonFits(width: 428, side: 20, windowControls: 66))
        #expect(TopBarPlacement.startButtonFits(width: 470, side: 20, windowControls: 66))
        #expect(TopBarPlacement.startButtonFits(width: 512, side: 20, windowControls: 66))
    }

    /// The dot bar takes touches on Aa, at its start, on an iPad, where a phone's has nothing and
    /// lets them through to the page. Aa takes them wherever its toolbar has it, which in a window
    /// that isn't full screen is well along, past the window's controls (user, 2026-10-09).
    @Test func aTapOnAaIsAas() {
        for isPad in [true, false] {
            let window = window(isPad: isPad)
            let bar = TopBarController(content: HStack(spacing: 0) {
                if isPad {
                    SystemBarButton(symbol: "textformat", title: "Format", edge: .leading, tint: .systemPurple) { _ in }
                        .frame(width: DotSwitcher.height, height: DotSwitcher.height)
                }
                Spacer()
            })
            bar.view.frame = CGRect(x: 0, y: 0, width: window.bounds.width, height: DotSwitcher.height)
            window.addSubview(bar.view)
            EditorHarness.show(window)
            bar.view.layoutIfNeeded()
            // The toolbar lays its button out a moment later.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let start = CGPoint(x: DotSwitcher.height / 2, y: DotSwitcher.height / 2)
            let hit = bar.view.hitTest(start, with: nil)
            let isAas = hit.map { sequence(first: $0, next: \.superview).contains { $0 is SystemBarButtonView } } ?? false
            #expect(isAas == isPad)
            // Beside it, the page's.
            #expect(bar.view.hitTest(CGPoint(x: DotSwitcher.height * 2, y: DotSwitcher.height / 2), with: nil) == nil)
            window.isHidden = true
        }
    }

    /// An iPad's corners are far less round than a phone's: the scroll indicator runs down to the
    /// home indicator's room, not 70 points short of the bottom.
    @Test func theScrollIndicatorRunsNearlyToTheBottom() {
        let editor = EditorHarness(String(repeating: "A line\n", count: 80))
        editor.textView.resignFirstResponder()
        editor.window.traitOverrides.userInterfaceIdiom = .pad
        editor.textView.updateTraitsIfNeeded()
        editor.textView.setNeedsLayout()
        editor.textView.layoutIfNeeded()
        let safeBottom = editor.window.safeAreaInsets.bottom
        #expect(editor.textView.verticalScrollIndicatorInsets.bottom == max(safeBottom, 20))
        editor.window.isHidden = true
    }

    /// The menu over the text, for the caret at `location`, as an iPad's or a phone's, its titles
    /// one after another.
    private func menuTitles(_ editor: EditorHarness, at location: Int, length: Int = 0) throws -> [String] {
        let view = editor.textView
        view.selectedRange = NSRange(location: location, length: length)
        let range = try #require(view.selectedTextRange)
        let suggested: [UIMenuElement] = [
            UIMenu(identifier: .standardEdit, options: .displayInline, children: [
                UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:))),
            ]),
        ]
        func titles(_ elements: [UIMenuElement]) -> [String] {
            elements.flatMap { ($0 as? UIMenu).map { titles($0.children) } ?? [$0.title] }
        }
        return titles(view.editMenu(for: range, suggestedActions: suggested)?.children ?? [])
    }

    /// With no link button on an iPad, links are added from the menu over the text, after Cut,
    /// Copy and Paste, as in Notes; a link's own menu has what a Mac's right-click has for one. A
    /// phone's menu has none of it: its bar has the button.
    @Test func linksAreAddedAndChangedFromTheMenu() throws {
        let editor = EditorHarness("Some [link](https://example.com) here")
        #expect(try menuTitles(editor, at: 2) == ["Copy"])
        editor.window.traitOverrides.userInterfaceIdiom = .pad
        editor.textView.updateTraitsIfNeeded()
        #expect(try menuTitles(editor, at: 2) == ["Copy", "Add Link…"])
        #expect(try menuTitles(editor, at: 7) == ["Copy", "Open Link", "Edit Link…", "Copy Link", "Remove Link"])
        // A selection in the link is the link's, as a caret in it is.
        #expect(try menuTitles(editor, at: 5, length: 2) == ["Copy", "Open Link", "Edit Link…", "Copy Link", "Remove Link"])
        editor.window.isHidden = true
    }

    /// The menu over selected text stays as it was: no Find, which finding on an iPad's page
    /// brought, nor Open in New Window, which Bite's windows did (user, 2026-10-09).
    @Test func theMenuOverTextHasNoFindNorNewWindow() throws {
        let editor = EditorHarness("Some words here")
        editor.window.traitOverrides.userInterfaceIdiom = .pad
        editor.textView.updateTraitsIfNeeded()
        let view = editor.textView
        view.selectedRange = NSRange(location: 5, length: 5)
        let range = try #require(view.selectedTextRange)
        let suggested: [UIMenuElement] = [
            UIMenu(identifier: .open, options: .displayInline, children: [
                UICommand(title: "Open in New Window", action: Selector(("_openInNewCanvas:"))),
            ]),
            UIMenu(identifier: .lookup, options: .displayInline, children: [
                UICommand(title: "Look Up", action: Selector(("_define:"))),
                UICommand(title: "Translate", action: Selector(("_translate:"))),
                UICommand(title: "Find", action: Selector(("findSelected:"))),
            ]),
        ]
        func titles(_ elements: [UIMenuElement]) -> [String] {
            elements.flatMap { ($0 as? UIMenu).map { titles($0.children) } ?? [$0.title] }
        }
        let shown = titles(view.editMenu(for: range, suggestedActions: suggested)?.children ?? [])
        #expect(!shown.contains("Find"))
        #expect(!shown.contains("Open in New Window"))
        #expect(shown.suffix(2) == ["Translate", "Look Up"])
        editor.window.isHidden = true
    }

    /// Add Link brings up the card, with the selected text as the link's; ✓ puts the link on the
    /// page as typed, as one edit.
    @Test func theCardPutsTheLinkOnThePage() {
        let (pager, page, window) = editingPager(isPad: true, markdown: "Some words")
        let sheet = LinkSheet.shared
        withExtendedLifetime(pager) {
            page.textView.selectedRange = NSRange(location: 5, length: 5)
            page.perform(.link)
            #expect(sheet.isPresented)
            #expect(sheet.title == "Add Link")
            #expect(sheet.text == "words")
            #expect(!sheet.canFinish)
            sheet.address = "example.com"
            #expect(sheet.canFinish)
            sheet.finish()
            #expect(!sheet.isPresented)
            #expect(page.markdownForTesting == "Some [words](https://example.com)")
        }
        window.isHidden = true
    }

    /// A finger's tap on a link while the page is being typed in brings up its card to change it
    /// in, Edit Link, as the phone's bar does: with no bar on an iPad's keys, it put the caret in
    /// the link and nothing more.
    @Test func tappingALinkWhileTypingBringsUpItsCard() throws {
        let (pager, page, window) = editingPager(isPad: true, markdown: "Some [words](https://example.com)")
        let sheet = LinkSheet.shared
        try withExtendedLifetime(pager) {
            page.textView.layoutIfNeeded()
            let frame = try #require(page.textView.textFramesForTesting(of: NSRange(location: 5, length: 5)).first)
            #expect(page.textView.tapLinkForTesting(at: CGPoint(x: frame.midX, y: frame.midY)))
            #expect(sheet.isPresented)
            #expect(sheet.title == "Edit Link")
            #expect(sheet.address == "https://example.com")
            sheet.cancel()
            #expect(page.markdownForTesting == "Some [words](https://example.com)")
        }
        window.isHidden = true
    }

    /// ✕ leaves the link as it was, and so does the card going with no address, by a tap outside
    /// it.
    @Test func cancellingLeavesThePageAsItWas() {
        let (pager, page, window) = editingPager(isPad: true, markdown: "Some [words](https://example.com)")
        let sheet = LinkSheet.shared
        withExtendedLifetime(pager) {
            page.textView.selectedRange = NSRange(location: 7, length: 0)
            page.perform(.link)
            #expect(sheet.title == "Edit Link")
            #expect(sheet.address == "https://example.com")
            sheet.address = "apple.com"
            sheet.cancel()
            #expect(page.markdownForTesting == "Some [words](https://example.com)")

            page.textView.selectedRange = NSRange(location: 7, length: 0)
            page.perform(.link)
            sheet.address = ""
            sheet.didDismiss()
            #expect(page.markdownForTesting == "Some [words](https://example.com)")
        }
        window.isHidden = true
    }

    /// The card is the system's form sheet, dimmed behind, named a size it's never at up to which
    /// it wouldn't be: dimmed throughout, the system put the keys away as it came and brought them
    /// back after it went, down and up again (user, 2026-10-09). A tap outside gives the keys to
    /// the page before the system takes them from the card.
    @Test func theCardKeepsTheKeysUp() throws {
        let window = window(isPad: true)
        let root = UIViewController()
        window.rootViewController = root
        let pager = DotPagerCoordinator()
        pager.container.frame = window.bounds
        root.view.addSubview(pager.container)
        EditorHarness.show(window)
        let page = pager.controllers[0]
        page.load(markdown: "Some [words](https://example.com)")
        page.focus()
        let sheet = LinkSheet.shared
        try withExtendedLifetime(pager) {
            page.textView.selectedRange = NSRange(location: 7, length: 0)
            page.perform(.link)
            let card = try #require(root.presentedViewController)
            #expect(card.modalPresentationStyle == .formSheet)
            #expect(card.sheetPresentationController?.largestUndimmedDetentIdentifier != nil)
            let presentation = try #require(card.presentationController)
            // As if the card's field had the keys.
            page.textView.resignFirstResponder()
            sheet.address = "apple.com"
            #expect(sheet.presentationControllerShouldDismiss(presentation))
            #expect(page.textView.isFirstResponder)
            sheet.presentationControllerDidDismiss(presentation)
            #expect(!sheet.isPresented)
            #expect(page.markdownForTesting == "Some [words](https://apple.com)")
        }
        window.isHidden = true
    }

    /// In a window as narrow as a phone, the card is the phone's drawer from the bottom, as Bite's
    /// other sheets are there: as tall as its form, with the grabber, in the drawer's glass, the
    /// keys kept up as ever. Made wider, it's the card in the middle again (user, 2026-10-09).
    @Test func theCardIsADrawerInANarrowWindow() throws {
        let window = window(isPad: true)
        window.traitOverrides.horizontalSizeClass = .compact
        let root = UIViewController()
        window.rootViewController = root
        let pager = DotPagerCoordinator()
        pager.container.frame = window.bounds
        root.view.addSubview(pager.container)
        EditorHarness.show(window)
        let page = pager.controllers[0]
        page.load(markdown: "Some words")
        page.focus()
        let sheet = LinkSheet.shared
        try withExtendedLifetime(pager) {
            page.perform(.link)
            let card = try #require(root.presentedViewController)
            let drawer = try #require(card.sheetPresentationController)
            #expect(drawer.detents.map(\.identifier) == [LinkSheet.fitted])
            #expect(drawer.prefersGrabberVisible)
            #expect(drawer.largestUndimmedDetentIdentifier != nil)
            #expect(sheet.isDrawer)
            #expect(card.view.backgroundColor == .clear)

            // The new width reaches the page as the window's laid out.
            window.traitOverrides.horizontalSizeClass = .regular
            window.updateTraitsIfNeeded()
            window.layoutIfNeeded()
            #expect(drawer.detents.map(\.identifier) == [.large])
            #expect(!drawer.prefersGrabberVisible)
            #expect(!sheet.isDrawer)
            #expect(card.view.backgroundColor != .clear)
            sheet.cancel()
        }
        window.isHidden = true
    }

    /// A web page comes up as the phone's sheet in a window as narrow as a phone, and as a card in
    /// the middle of a wider one (user, 2026-10-09).
    @Test func aWebPageIsThePhonesSheetInANarrowWindow() throws {
        for isNarrow in [true, false] {
            let window = window(isPad: true)
            window.traitOverrides.horizontalSizeClass = isNarrow ? .compact : .regular
            let root = UIViewController()
            window.rootViewController = root
            let page = EditorController(dot: 0, accent: .systemOrange)
            page.textView.frame = window.bounds
            root.view.addSubview(page.textView)
            EditorHarness.show(window)
            page.textView.showWebPage(try #require(URL(string: "https://example.com")))
            let safari = try #require(root.presentedViewController)
            #expect(safari.modalPresentationStyle == (isNarrow ? .pageSheet : .formSheet))
            safari.dismiss(animated: false)
            window.isHidden = true
        }
    }

    /// The format panel acts on the page as Bite's styles, and shows what's on: a style, a
    /// heading, a list, a to-do, a quote, each kind of line pressed again going back to text.
    @Test func theFormatPanelStylesThePage() {
        let editor = EditorHarness("Some words")
        let panel = FormatPanel.shared
        editor.textView.selectedRange = NSRange(location: 5, length: 5)
        panel.perform(.bold)
        #expect(editor.markdown == "Some **words**")
        #expect(panel.lit == [.bold])
        #expect(panel.lineStyle == .paragraph)
        panel.setLineStyle(.heading2)
        #expect(editor.markdown == "## Some **words**")
        #expect(panel.lineStyle == .heading2)
        panel.perform(.ordered)
        #expect(editor.markdown == "1. Some **words**")
        #expect(panel.lit == [.bold, .ordered])
        #expect(panel.lineStyle == nil)
        panel.perform(.todo)
        #expect(editor.markdown == "- [ ] Some **words**")
        panel.perform(.todo)
        #expect(editor.markdown == "Some **words**")
        panel.perform(.quote)
        #expect(editor.markdown == "> Some **words**")
        #expect(panel.lit == [.bold, .quote])
        panel.setLineStyle(.paragraph)
        panel.perform(.bold)
        #expect(editor.markdown == "Some words")
        #expect(panel.lit.isEmpty)
        editor.window.isHidden = true
    }
}
