import Testing
import UIKit
import BiteKit
@testable import Bite

/// Which styles the format bar shows as on: they tell what typing will do, and tapping one
/// that's on undoes it.
struct FormatBarStateTests {
    @Test func boldStaysOnUntilTappedAgain() {
        let editor = EditorHarness("a")
        editor.moveCaret(line: 0)
        #expect(!FormatBar.shared.showsOn(.bold))
        editor.controller.perform(.bold)
        #expect(FormatBar.shared.showsOn(.bold))
        editor.type("b")
        #expect(FormatBar.shared.showsOn(.bold))
        editor.controller.perform(.bold)
        #expect(!FormatBar.shared.showsOn(.bold))
        editor.type("c")
        #expect(editor.markdown == "a**b**c")
    }

    @Test func caretFollowsTheTextBeforeIt() {
        let editor = EditorHarness("a **b** c")
        editor.moveCaret(line: 0, column: 3)
        #expect(editor.controller.activeStyles == .bold)
        editor.moveCaret(line: 0, column: 5)
        #expect(editor.controller.activeStyles.isEmpty)
    }

    @Test func tappingBoldAfterBoldTextTurnsItOff() {
        let editor = EditorHarness("**a**")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bold)
        editor.type("b")
        #expect(editor.markdown == "**a**b")
    }

    @Test func selectionShowsWhatAllOfItHas() {
        let editor = EditorHarness("***ab*** *c*")
        editor.select(from: (0, 0), to: (0, 2))
        #expect(editor.controller.activeStyles == [.bold, .italic])
        editor.select(from: (0, 0), to: (0, 4))
        #expect(editor.controller.activeStyles.isEmpty)
    }

    @Test func lineBreaksDontCountInASelection() {
        let editor = EditorHarness("- **ab**\n- **cd**")
        editor.select(from: (0, 1), to: (1, 1))
        #expect(editor.controller.activeStyles == .bold)
        editor.controller.perform(.bold)
        #expect(editor.markdown == "- **a**b\n- c**d**")
    }

    /// A line's kind shows on the page itself.
    @Test func lineKindsDontShowOnTheBar() {
        let editor = EditorHarness("- [ ] a")
        editor.moveCaret(line: 0)
        #expect(!FormatBar.shared.showsOn(.todo))
        editor.controller.perform(.quote)
        #expect(!FormatBar.shared.showsOn(.quote))
    }

    @Test func codeTakesNoInlineStyle() {
        let editor = EditorHarness("```\nx\n```")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bold)
        #expect(editor.controller.activeStyles.isEmpty)
        editor.type("y")
        #expect(editor.markdown == "```\nxy\n```")
    }
}

/// Where the bar sits while a page is edited: on top of the keys, unless something else needs
/// the room there.
@MainActor
struct FormatBarPlacementTests {
    /// The pages in a window, the first being edited, over keys `keys` tall.
    private func editingPager(keys: CGFloat) -> (pager: DotPagerCoordinator, page: EditorController, window: UIWindow) {
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
        pager.container.keysForTesting = keys
        let page = pager.controllers[0]
        page.load(markdown: "Some words to rewrite")
        page.focus()
        pager.container.layoutIfNeeded()
        return (pager, page, window)
    }

    private func setKeys(_ keys: CGFloat, in pager: DotPagerCoordinator) {
        pager.container.keysForTesting = keys
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
    }

    /// Writing Tools at work on the page brings controls of its own, a panel where the keys were.
    /// The bar stayed on top of it, its buttons there to be pressed while the text was being
    /// rewritten. Once it's done, the bar comes back with the keys, from the bottom of the
    /// screen: back at once, it slid up onto the panel as the panel went, and then sat high above
    /// the keys as they came up.
    @Test func theBarMakesWayForWritingTools() {
        let (pager, page, window) = editingPager(keys: 336)
        let height = window.bounds.height
        #expect(page.textView.keyboardOverlap == 336 + FormatBar.height)

        page.textViewWritingToolsWillBegin(page.textView)
        setKeys(201, in: pager)
        #expect(FormatBar.shared.accessibilityElementsHidden)
        #expect(page.textView.keyboardOverlap == 201)
        #expect(pager.container.barTrackFrameForTesting.maxY == height)

        page.textViewWritingToolsDidEnd(page.textView)
        pager.container.layoutIfNeeded()
        #expect(FormatBar.shared.accessibilityElementsHidden)
        #expect(page.textView.keyboardOverlap == 201)
        #expect(pager.container.barTrackFrameForTesting.maxY == height)

        setKeys(336, in: pager)
        #expect(!FormatBar.shared.accessibilityElementsHidden)
        #expect(page.textView.keyboardOverlap == 336 + FormatBar.height)
        #expect(pager.container.barTrackFrameForTesting.maxY == height - 336)
    }

    /// Keys that stay as they were once Writing Tools is done leave the bar waiting only a moment.
    @Test func theBarComesBackOnItsOwnAfterWritingTools() async {
        let (pager, page, window) = editingPager(keys: 336)
        page.textViewWritingToolsWillBegin(page.textView)
        page.textViewWritingToolsDidEnd(page.textView)
        #expect(page.textView.keyboardOverlap == 336)
        for _ in 0..<20 where page.textView.keyboardOverlap != 336 + FormatBar.height {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.textView.keyboardOverlap == 336 + FormatBar.height)
        #expect(pager.container.barTrackFrameForTesting.maxY == window.bounds.height - 336)
    }
}
