#if !canImport(UIKit)
import AppKit
import Testing
import BiteKit
@testable import Bite

/// The panel the menu bar ring opens. A store of the tests' own leaves the app's pages alone.
/// One at a time: which window has the keyboard is the whole app's, and a test waiting a moment
/// found the keyboard back with its panel as another test's window went.
@MainActor
@Suite(.serialized)
struct MacPanelTests {
    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BitePanelTests-\(UUID().uuidString)"))
    }

    private func panel(_ store: DotStore? = nil) -> PanelController {
        PanelController(store: store ?? self.store(), forTesting: true)
    }

    private func otherWindow() -> BitePanel {
        BitePanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered, defer: false)
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Esc in the text goes past AppKit's completions, up to the panel, which puts itself away.
    @Test func escapeAndCommandWPutThePanelAway() {
        let panel = BitePanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        var cancels = 0
        panel.onCancel = { cancels += 1 }
        let textView = BiteTextView()
        textView.configure()
        panel.contentView = textView
        panel.makeFirstResponder(textView)
        textView.cancelOperation(nil)
        #expect(cancels == 1)
        panel.performClose(nil)
        #expect(cancels == 2)
    }

    @Test func theMenuIsLaidOutAsOnThePhone() {
        let store = store()
        let panel = panel(store)
        let menu = panel.makeMenu()
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Settings…", "Statistics", "-", "Copy Markdown", "Copy Plain Text", "Clear Text", "-", "Share Text",
                           "-", "Quit Bite"])
        // Rows of Bite's own, with the phone's pictures and the page's colour for the highlight,
        // chosen from the keyboard too; and the keys Bite's menus give the same commands.
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.view is MenuRow, "\(item.title)")
        }
        #expect(menu.delegate === MenuRow.keyboard)
        #expect(menu.items.first { $0.title == "Settings…" }?.keyEquivalent == ",")
        #expect(menu.items.first { $0.title == "Quit Bite" }?.keyEquivalent == "q")
        // Nothing in red, and nothing to copy, clear or share on an empty page.
        let hasText = !store.isEmpty[store.selection]
        for title in ["Copy Markdown", "Copy Plain Text", "Clear Text", "Share Text"] {
            #expect(menu.items.first { $0.title == title }?.isEnabled == hasText)
        }
    }

    /// Statistics opens a menu of its own with the page's words, characters and paragraphs, and
    /// when it last changed, as the phone's drawer shows them. Its rows only say something.
    @Test func statisticsSaysWhatThePageHolds() throws {
        let store = store()
        store.update(dot: store.selection, markdown: "# Plan\n- two words\n")
        let menu = panel(store).makeMenu()
        let statistics = try #require(menu.items.first { $0.title == "Statistics" })
        #expect(statistics.view is MenuRow)
        let rows = try #require(statistics.submenu).items
        #expect(rows.map { $0.isSeparatorItem ? "-" : $0.title } == ["Words", "Characters", "Paragraphs", "-", "Modified"])
        for row in rows where !row.isSeparatorItem {
            #expect(!row.isEnabled && row.view is MenuRow, "\(row.title)")
        }
        #expect(rows[0].view?.accessibilityLabel() == "Words, 3")
        #expect(rows[1].view?.accessibilityLabel() == "Characters, 13")
        #expect(rows[2].view?.accessibilityLabel() == "Paragraphs, 2")
        let modified = try #require(store.modified[store.selection])
        #expect(rows[4].view?.accessibilityLabel() == "Modified, \(ModifiedDate.text(modified))")
    }

    /// Put away, the panel shrinks a little as its window clears, taking no clicks or keys
    /// meanwhile, and is gone once it has. Its going starts at once, not after the rest of the
    /// putting away. Shown again meanwhile, it's back as it was and stays.
    @Test func thePanelShrinksAwayAndCanComeBackMeanwhile() async {
        let panel = panel()
        let window = panel.windowForTesting
        // Ten times as slow, to look at it partway.
        panel.animateClosingForTesting(slowdown: 10)
        panel.show()
        panel.hide()
        #expect(!panel.isShown)
        #expect(window.isVisible)
        #expect(window.ignoresMouseEvents)
        #expect(panel.isClosingForTesting)
        #expect(panel.closeHasBegunForTesting)
        // Partway, the window is clearing, its shadow with it. AppKit steps it on the main thread,
        // which tests running alongside can hold for a moment, so it's looked at until it is.
        var clearing = false
        for _ in 0..<40 where !clearing {
            await wait(0.02)
            clearing = window.alphaValue < 1 && window.alphaValue > 0
        }
        #expect(clearing)
        panel.show()
        #expect(panel.isShown)
        #expect(window.alphaValue == 1)
        #expect(!panel.isClosingForTesting)
        await wait(0.3)
        #expect(window.isVisible)
        #expect(!window.ignoresMouseEvents)
        panel.hide()
        await wait(1.6)
        #expect(!window.isVisible)
        #expect(window.alphaValue == 1)
        #expect(!panel.isClosingForTesting)
    }

    /// The ring's right click has Bite's own commands, none of the page's.
    @Test func theRingsMenuIsBitesOwn() {
        let menu = panel().makeRingMenu()
        #expect(menu.items.map { $0.isSeparatorItem ? "-" : $0.title } == ["Settings…", "-", "Quit Bite"])
        #expect(menu.items.allSatisfy { $0.isSeparatorItem || $0.view is MenuRow })
        #expect(menu.delegate === MenuRow.keyboard)
    }

    /// The ring closes what it opened. The panel had the keyboard without Bite being the
    /// active app, and a second click opened it again instead.
    @Test func theRingClosesWhatItOpened() {
        let panel = panel()
        panel.toggle()
        #expect(panel.isShown)
        panel.toggle()
        #expect(!panel.isShown)
    }

    /// Clicking anything else puts the panel away, and the click on the ring that does it is the
    /// one that closes it, not one that opens it again.
    @Test func clickingElsewherePutsItAway() {
        let panel = panel()
        panel.show()
        let other = otherWindow()
        panel.clickedOutside()
        other.makeKeyAndOrderFront(nil)
        #expect(!panel.isShown)
        panel.toggle()
        #expect(!panel.isShown)
        other.orderOut(nil)
    }

    /// The keyboard can go before the click that took it is heard.
    @Test func theKeyboardGoingBeforeTheClickIsHeard() {
        let panel = panel()
        panel.show()
        let other = otherWindow()
        other.makeKeyAndOrderFront(nil)
        #expect(panel.isShown)
        panel.clickedOutside()
        #expect(!panel.isShown)
        other.orderOut(nil)
    }

    /// A swipe to another Space takes the keyboard, and the panel, there too, stays. In either
    /// order: the Space changing, then the keyboard going, or the other way round. A click
    /// elsewhere puts it away after all.
    @Test(arguments: [true, false])
    func aSwipeToAnotherSpaceKeepsItOpen(spaceFirst: Bool) async {
        let panel = panel()
        panel.show()
        let other = otherWindow()
        if spaceFirst { panel.activeSpaceDidChange() }
        other.makeKeyAndOrderFront(nil)
        if !spaceFirst { panel.activeSpaceDidChange() }
        await wait(0.7)
        #expect(panel.isShown)
        panel.clickedOutside()
        #expect(!panel.isShown)
        other.orderOut(nil)
    }

    /// Dragged away from the ring, the panel stays where it's put, whatever's clicked, until it's
    /// closed. Then it goes back below the ring.
    @Test func aPanelDraggedAwayStaysUntilClosed() async {
        let panel = panel()
        panel.show()
        let window = panel.windowForTesting
        let belowTheRing = window.frame
        panel.windowWillMove(Notification(name: NSWindow.willMoveNotification, object: window))
        #expect(panel.placement.isDetached)
        window.setFrameOrigin(NSPoint(x: belowTheRing.minX - 200, y: belowTheRing.minY - 150))
        let other = otherWindow()
        other.makeKeyAndOrderFront(nil)
        panel.clickedOutside()
        await wait(0.7)
        #expect(panel.isShown)
        // Shown again where it is, as when Bite is opened from Finder.
        panel.show()
        #expect(window.frame.origin == NSPoint(x: belowTheRing.minX - 200, y: belowTheRing.minY - 150))
        // Its close button, the ring, Esc and Command-W all close it.
        panel.hide()
        #expect(!panel.isShown)
        #expect(!panel.placement.isDetached)
        panel.show()
        #expect(window.frame.origin == belowTheRing.origin)
        panel.hide()
        other.orderOut(nil)
    }

    /// Put below the ring, or resized from its corner, the panel isn't being dragged away.
    @Test func movedOrResizedInCodeItStaysWithTheRing() {
        let panel = panel()
        panel.show()
        let window = panel.windowForTesting
        var frame = window.frame
        frame.origin.x -= 40
        frame.size.height -= 30
        window.setFrame(frame, display: false)
        window.setFrameOrigin(NSPoint(x: frame.minX + 10, y: frame.minY + 10))
        #expect(!panel.placement.isDetached)
        panel.hide()
    }

    /// Nothing heard, as for Command-Tab on this Space: it goes a moment later.
    @Test func withNothingHeardItGoesAMomentLater() async {
        let panel = panel()
        panel.show()
        let other = otherWindow()
        other.makeKeyAndOrderFront(nil)
        #expect(panel.isShown)
        await wait(0.7)
        #expect(!panel.isShown)
        other.orderOut(nil)
    }

    private func key(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags, in window: NSWindow) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: keyCode)
    }

    /// Bite isn't the active app while the panel has the keyboard, and its menus' shortcuts
    /// still reach the page.
    @Test func shortcutsReachThePage() throws {
        let store = store()
        let panel = panel(store)
        panel.show()
        defer { panel.hide() }
        let page = panel.controllers[store.selection]
        page.load(markdown: "word")
        page.textView.selectedRange = NSRange(location: 0, length: 4)
        let window = panel.windowForTesting
        let commandB = try #require(key("b", keyCode: 11, .command, in: window))
        #expect(window.performKeyEquivalent(with: commandB))
        #expect(page.markdownForTesting == "**word**")
    }

    /// Esc, typed in the page, puts the panel away.
    @Test func escapeTypedInThePage() throws {
        let store = store()
        let panel = panel(store)
        panel.show()
        let window = panel.windowForTesting
        #expect(window.firstResponder === panel.controllers[store.selection].textView)
        let escape = try #require(key("\u{1B}", keyCode: 53, [], in: window))
        window.sendEvent(escape)
        #expect(!panel.isShown)
    }

    /// Two fingers sliding sideways: the pages follow, the dot bar shows the page mostly on screen,
    /// and the swipe lands on the page beside.
    @Test func aSwipeMovesToThePageBeside() throws {
        let original = UserDefaults.standard.object(forKey: "selectedDot")
        defer { UserDefaults.standard.set(original, forKey: "selectedDot") }
        let store = store()
        store.selection = 1
        let panel = panel(store)
        let pages = panel.controllers.map { $0.textView.enclosingScrollView }
        let width = try #require(pages[1]?.superview?.bounds.width)
        panel.showSwipe(page: 1, offset: -0.3 * width)
        #expect(pages[1]?.frame.minX == -0.3 * width)
        // A page's width on from the offset, which at some widths isn't 0.7 of it to the last bit.
        #expect(abs((pages[2]?.frame.minX ?? 0) - 0.7 * width) < 0.001)
        #expect(pages.indices.filter { pages[$0]?.isHidden == false } == [1, 2])
        #expect(panel.onScreen.page == nil)
        panel.showSwipe(page: 1, offset: -0.6 * width)
        #expect(panel.onScreen.page == 2)
        panel.land(on: 2)
        #expect(store.selection == 2)
        #expect(pages.indices.filter { pages[$0]?.isHidden == false } == [2])
        #expect(pages[2]?.frame.minX == 0)
        #expect(panel.onScreen.page == nil)
    }

    /// Past the first page there's none to come in.
    @Test func pastTheFirstPageNothingComesIn() {
        let original = UserDefaults.standard.object(forKey: "selectedDot")
        defer { UserDefaults.standard.set(original, forKey: "selectedDot") }
        let store = store()
        store.selection = 0
        let panel = panel(store)
        let pages = panel.controllers.map { $0.textView.enclosingScrollView }
        panel.showSwipe(page: 0, offset: 30)
        #expect(pages.indices.filter { pages[$0]?.isHidden == false } == [0])
        panel.land(on: 0)
        #expect(store.selection == 0)
        #expect(pages[0]?.frame.minX == 0)
    }

    /// Picking a dot shows its page, and only its page.
    @Test func eachDotShowsItsOwnPage() {
        let store = store()
        let panel = panel(store)
        let pages = panel.controllers.map { $0.textView.enclosingScrollView }
        #expect(pages.filter { $0?.isHidden == false }.count == 1)
        #expect(pages[store.selection]?.isHidden == false)
    }
}
#endif
