#if !canImport(UIKit)
import AppKit
import Testing
import BiteKit
@testable import Bite

/// The panel the menu bar ring opens. A store of the tests' own leaves the app's pages alone.
@MainActor
struct MacPanelTests {
    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BitePanelTests-\(UUID().uuidString)"))
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
        let panel = PanelController(store: store)
        let menu = panel.makeMenu()
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles == ["Settings…", "-", "Copy Markdown", "Copy Plain Text", "Clear Text", "-", "Share Text", "-",
                           "Keep Window Open", "Quit Bite"])
        // Nothing in red, and nothing to copy, clear or share on an empty page.
        let hasText = !store.isEmpty[store.selection]
        for title in ["Copy Markdown", "Copy Plain Text", "Clear Text", "Share Text"] {
            #expect(menu.items.first { $0.title == title }?.isEnabled == hasText)
        }
    }

    /// The ring closes what it opened. The panel had the keyboard without Bite being the
    /// active app, and a second click opened it again instead.
    @Test func theRingClosesWhatItOpened() {
        let panel = PanelController(store: store())
        panel.toggle()
        #expect(panel.isShown)
        panel.toggle()
        #expect(!panel.isShown)
    }

    /// Clicking anything else puts the panel away, and the click on the ring that does it is the
    /// one that closes it, not one that opens it again.
    @Test func clickingElsewherePutsItAway() {
        let panel = PanelController(store: store())
        panel.show()
        let other = BitePanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        other.makeKeyAndOrderFront(nil)
        #expect(!panel.isShown)
        panel.toggle()
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
        let panel = PanelController(store: store)
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
        let panel = PanelController(store: store)
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
        let panel = PanelController(store: store)
        let pages = panel.controllers.map { $0.textView.enclosingScrollView }
        let width = try #require(pages[1]?.superview?.bounds.width)
        panel.showSwipe(page: 1, offset: -0.3 * width)
        #expect(pages[1]?.frame.minX == -0.3 * width)
        #expect(pages[2]?.frame.minX == 0.7 * width)
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
        let panel = PanelController(store: store)
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
        let panel = PanelController(store: store)
        let pages = panel.controllers.map { $0.textView.enclosingScrollView }
        #expect(pages.filter { $0?.isHidden == false }.count == 1)
        #expect(pages[store.selection]?.isHidden == false)
    }
}
#endif
