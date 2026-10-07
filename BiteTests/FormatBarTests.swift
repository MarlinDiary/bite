import Testing
import UIKit
import BiteKit
@testable import Bite

/// The format bar's buttons: in the order asked for, the first six across it as it comes up, and
/// the button putting the keys away a seventh, the bar's width shared evenly between them.
@MainActor
struct FormatBarButtonsTests {
    private static let order: [FormatAction] = [.heading, .todo, .bold, .italic, .strikethrough, .link,
                                                .quote, .code, .outdent, .indent, .ordered, .bullet]

    /// The bar on the keys of a pager in an upright window `width` wide, as on a phone that wide:
    /// one bar serves every pager, and one turned on its side before had it half as wide.
    private func pager(width: CGFloat) -> (pager: DotPagerCoordinator, window: UIWindow) {
        let pager = DotPagerCoordinator()
        let frame = CGRect(x: 0, y: 0, width: width, height: 874)
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
        pager.container.layoutIfNeeded()
        FormatBar.shared.layoutIfNeeded()
        return (pager, window)
    }

    @Test func theFirstSixShowAsTheBarComesUp() {
        for width in [375.0, 402, 420, 440] {
            let (pager, window) = pager(width: width)
            let bar = FormatBar.shared
            bar.showFirstButtons()
            let along = bar.buttonsAlongTheBar
            #expect(along.map(\.action) == Self.order)
            #expect(along.filter(\.isWhole).map(\.action) == Array(Self.order.prefix(6)), "\(width)")
            #expect(bar.buttonGapsForTesting.allSatisfy { abs($0 - bar.buttonGapsForTesting[0]) < 0.5 }, "\(width)")
            window.isHidden = true
            withExtendedLifetime(pager) {}
        }
    }

    /// Paged along, the bar shows the other six, and comes up again with the first.
    @Test func theOtherSixAreAPageAway() {
        let (pager, window) = pager(width: 402)
        defer {
            FormatBar.shared.showFirstButtons()
            window.isHidden = true
            withExtendedLifetime(pager) {}
        }
        let bar = FormatBar.shared
        bar.scrollButtonsToEnd()
        #expect(bar.buttonsAlongTheBar.filter(\.isWhole).map(\.action) == Array(Self.order.suffix(6)))
        bar.showFirstButtons()
        #expect(bar.buttonsAlongTheBar.filter(\.isWhole).map(\.action) == Array(Self.order.prefix(6)))
    }
}

/// The heading button opens a menu of the heading levels, made as it opens, the line's ticked. It
/// comes out of the bar's whole glass, which the system turns into the menu and back, as Notes'
/// keyboard toolbar does. A level chosen goes onto every line the caret or selection is on.
@MainActor
struct HeadingMenuTests {
    private var bar: FormatBar { FormatBar.shared }

    /// The pages in a window, the first being edited with `markdown` on it, over keys 336 tall.
    private func editingPager(_ markdown: String) -> (pager: DotPagerCoordinator, page: EditorController, window: UIWindow) {
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
        pager.container.keysForTesting = 336
        pager.container.setNeedsLayout()
        pager.container.layoutIfNeeded()
        return (pager, page, window)
    }

    private func finish(_ pager: DotPagerCoordinator, _ window: UIWindow) {
        window.isHidden = true
        withExtendedLifetime(pager) {}
    }

    /// On a heading, the menu offers plain text too, above the levels with a line between, as
    /// Notes' list styles offer None only on a list; on any other line, the levels alone.
    @Test func itOffersTheLevelsWithTheLinesTicked() {
        let (pager, page, window) = editingPager("# Title\nWords")
        defer { finish(pager, window) }
        #expect(bar.headingMenuComesOutOfTheGlassForTesting)
        page.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(bar.headingMenuForTesting.map(\.title) == ["Text", "Heading 1", "Heading 2", "Heading 3"])
        #expect(bar.headingMenuForTesting.filter(\.isTicked).map(\.title) == ["Heading 1"])
        #expect(bar.headingMenuGroupsForTesting == 2)
        page.textView.selectedRange = NSRange(location: 9, length: 0)
        #expect(bar.headingMenuForTesting.map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
        #expect(bar.headingMenuForTesting.allSatisfy { !$0.isTicked })
        #expect(bar.headingMenuGroupsForTesting == 1)
    }

    @Test func aLevelChosenGoesOntoTheLine() {
        let (pager, page, window) = editingPager("# Title\nWords")
        defer { finish(pager, window) }
        page.textView.selectedRange = NSRange(location: 2, length: 0)
        bar.chooseHeadingForTesting("Heading 2")
        #expect(page.markdownForTesting == "## Title\nWords")
        #expect(bar.headingMenuForTesting.filter(\.isTicked).map(\.title) == ["Heading 2"])
        bar.chooseHeadingForTesting("Text")
        #expect(page.markdownForTesting == "Title\nWords")
        // Every line the selection is on.
        page.textView.selectedRange = NSRange(location: 0, length: 9)
        bar.chooseHeadingForTesting("Heading 3")
        #expect(page.markdownForTesting == "### Title\n### Words")
    }

    /// A list's line is none of the levels: none is ticked, and one chosen makes it a heading.
    @Test func aListsLineBecomesAHeading() {
        let (pager, page, window) = editingPager("- [ ] Milk")
        defer { finish(pager, window) }
        page.textView.selectedRange = NSRange(location: 2, length: 0)
        #expect(bar.headingMenuForTesting.map(\.title) == ["Heading 1", "Heading 2", "Heading 3"])
        #expect(bar.headingMenuForTesting.allSatisfy { !$0.isTicked })
        bar.chooseHeadingForTesting("Heading 1")
        #expect(page.markdownForTesting == "# Milk")
    }
}

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
        let page = pager.controllers[0]
        page.load(markdown: "Some words to rewrite")
        page.focus()
        // Laid out over the keys even when the window has been laid out already.
        setKeys(keys, in: pager)
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

    /// Siri takes the keys for its own and gives them back, and each time UIKit first says they've
    /// gone, then a few milliseconds later that they're back. The bar stays where it was: following
    /// that, it dipped and bounced back, or fell and dropped back down from above.
    @Test func keysGoneForAMomentLeaveTheBarWhereItIs() {
        let (pager, page, window) = editingPager(keys: 336)
        let track = pager.container.barTrackFrameForTesting
        let overlap = page.textView.keyboardOverlap
        setKeys(0, in: pager)
        #expect(pager.container.barTrackFrameForTesting == track)
        #expect(page.textView.keyboardOverlap == overlap)
        setKeys(336, in: pager)
        #expect(pager.container.barTrackFrameForTesting == track)
        #expect(page.textView.keyboardOverlap == overlap)
        #expect(window.bounds.height > track.maxY)
    }

    /// Keys still gone a moment later, as for a hardware keyboard, take the bar with them.
    @Test func keysGoneForGoodTakeTheBarAfterAMoment() async {
        let (pager, page, window) = editingPager(keys: 336)
        setKeys(0, in: pager)
        for _ in 0..<20 where page.textView.keyboardOverlap != 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.textView.keyboardOverlap == 0)
        #expect(pager.container.barTrackFrameForTesting.maxY == window.bounds.height)
    }

    /// Keys that say they're going, as when Writing Tools is about to take their place, take the
    /// bar with them at once.
    @Test func keysSayingTheyreGoingTakeTheBarAtOnce() {
        let (pager, page, window) = editingPager(keys: 336)
        let center = NotificationCenter.default
        center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        defer { center.post(name: UIResponder.keyboardWillShowNotification, object: nil) }
        setKeys(0, in: pager)
        #expect(page.textView.keyboardOverlap == 0)
        #expect(pager.container.barTrackFrameForTesting.maxY == window.bounds.height)
    }

    /// Keys put away with the page, as the bar's own button puts them away, take the bar at once.
    @Test func keysPutAwayTakeTheBarAtOnce() {
        let (pager, page, window) = editingPager(keys: 336)
        page.textView.resignFirstResponder()
        setKeys(0, in: pager)
        #expect(pager.container.barTrackFrameForTesting.maxY == window.bounds.height)
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
