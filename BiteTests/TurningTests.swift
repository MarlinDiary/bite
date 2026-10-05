import Testing
import UIKit
@testable import Bite

/// Turning the phone: the pager stays on its page and a page keeps its place, and on a phone on
/// its side the dot bar goes up out of the way of the keys and the format bar takes half the width.
@MainActor
struct TurningTests {
    private static let upright = CGRect(x: 0, y: 0, width: 402, height: 874)
    private static let onItsSide = CGRect(x: 0, y: 0, width: 874, height: 402)

    private func window(_ frame: CGRect) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        EditorHarness.show(window)
        return window
    }

    private func pager(on page: Int) -> (DotPagerCoordinator, UIWindow) {
        let pager = DotPagerCoordinator()
        let window = window(Self.upright)
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        for controller in pager.controllers {
            controller.load(markdown: "Page \(controller.dot)")
        }
        pager.container.layoutIfNeeded()
        pager.scrollView.go(to: page)
        return (pager, window)
    }

    private func turn(_ view: UIView, to frame: CGRect, in window: UIWindow) {
        window.frame = frame
        view.frame = window.bounds
        view.layoutIfNeeded()
    }

    /// A page of paragraphs long enough to wrap differently either way up.
    private func page(in window: UIWindow) -> EditorController {
        let page = EditorController(dot: 1, accent: .systemBlue)
        page.textView.frame = window.bounds
        window.addSubview(page.textView)
        let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 6)
        page.load(markdown: (1...30).map { "Paragraph \($0). \(paragraph)" }.joined(separator: "\n\n"))
        page.textView.layoutIfNeeded()
        return page
    }

    /// The character starting the line at the top of what shows, under the dot bar.
    private func topCharacter(of textView: BiteTextView) -> Int {
        let point = CGPoint(x: textView.textContainerInset.left + 1, y: textView.contentOffset.y + textView.contentInset.top + 1)
        let position = textView.closestPosition(to: point) ?? textView.beginningOfDocument
        return textView.offset(from: textView.beginningOfDocument, to: position)
    }

    /// How far below the dot bar the line with `location` in it starts.
    private func lineTop(of location: Int, in textView: BiteTextView) -> CGFloat {
        let position = textView.position(from: textView.beginningOfDocument, offset: location) ?? textView.beginningOfDocument
        return textView.caretRect(for: position).minY - (textView.contentOffset.y + textView.contentInset.top)
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Turned upright again, the pages narrowed under the pager's old place and put it on the last
    /// page for a moment, which it reported, and the dot bar was left on it.
    @Test func thePagerStaysOnItsPage() {
        let (pager, window) = pager(on: 4)
        var reported: [Int] = []
        pager.showVisiblePage = { reported.append($0) }
        for frame in [Self.onItsSide, Self.upright, Self.onItsSide, Self.upright] {
            turn(pager.container, to: frame, in: window)
            #expect(pager.scrollView.contentOffset.x == 4 * frame.width)
        }
        #expect(reported.isEmpty)
    }

    /// The line at the top stays at the top as the lines reflow, and turned back with nothing
    /// changed, the page is back just where it was.
    @Test func aPageKeepsTheLineAtItsTop() async {
        let window = window(Self.upright)
        let textView = page(in: window).textView
        textView.contentOffset.y = 900
        textView.layoutIfNeeded()
        let location = topCharacter(of: textView)
        let below = lineTop(of: location, in: textView)
        turn(textView, to: Self.onItsSide, in: window)
        #expect(abs(lineTop(of: location, in: textView) - below) < 1)
        #expect(abs(textView.contentOffset.y - 900) > 100)
        await wait(0.7)
        turn(textView, to: Self.upright, in: window)
        #expect(abs(textView.contentOffset.y - 900) < 1)
    }

    /// Typing, the caret stays in view of the keys as they turn too, and turned back, the page is
    /// where it was. It used to scroll by the keys' height from before the turn, too far, and then
    /// back once the turn was over.
    @Test func typingTheCaretStaysInViewOfTheKeys() async {
        let window = window(Self.upright)
        let page = page(in: window)
        let textView = page.textView
        textView.keyboardOverlap = 336
        page.focus()
        textView.selectedRange = NSRange(location: 2500, length: 0)
        textView.layoutIfNeeded()
        await wait(0.5)
        // Scrolled to where the caret is well in view, a little below the dot bar.
        let caretTop = textView.caretRect(for: textView.selectedTextRange!.end).minY
        textView.contentOffset.y = caretTop - textView.contentInset.top - 100
        textView.layoutIfNeeded()
        let before = textView.contentOffset.y
        // The test window doesn't turn, so its safe area stays upright: shorter keys leave the
        // page as much room as a phone on its side has.
        turn(textView, to: Self.onItsSide, in: window)
        textView.keyboardOverlap = 150
        textView.layoutIfNeeded()
        let caret = textView.caretRect(for: textView.selectedTextRange!.end)
        #expect(caret.minY >= textView.contentOffset.y + textView.contentInset.top - 1)
        #expect(caret.maxY <= textView.contentOffset.y + textView.bounds.height - 150 + 1)
        await wait(0.7)
        turn(textView, to: Self.upright, in: window)
        textView.keyboardOverlap = 336
        textView.layoutIfNeeded()
        #expect(abs(textView.contentOffset.y - before) < 1)
    }

    /// On a phone on its side the keys leave the page a few lines: the dot bar goes up out of their
    /// way while they're up, and comes back as they go. Upright, it stays. It moves in the keys' own
    /// animation, in UIKit, which the phone holding the main thread as the keys come can't stop.
    @Test func theDotBarGoesUpOutOfTheWayOfTheKeysOnItsSide() {
        let (pager, window) = pager(on: 2)
        let mover = TopBarMover()
        let bar = UIView()
        mover.attachForTesting(bar, lift: 76)
        pager.topBarMover = mover
        let container = pager.container
        pager.controllers[2].focus()
        container.keysForTesting = 300
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(!mover.isAway)
        container.traitOverrides.verticalSizeClass = .compact
        UIView.animate(withDuration: 0.3) {
            container.setNeedsLayout()
            container.layoutIfNeeded()
        }
        #expect(mover.isAway)
        #expect(pager.controllers.allSatisfy { $0.textView.isTopBarAway })
        #expect(bar.alpha == 0 && bar.transform.ty == -76)
        #expect(bar.layer.animation(forKey: "opacity") != nil)
        pager.controllers[2].textView.resignFirstResponder()
        container.keysForTesting = 0
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(!mover.isAway)
        #expect(!pager.controllers[2].textView.isTopBarAway)
        #expect(bar.alpha == 1 && bar.transform == .identity)
        _ = window
    }

    /// As Notes' toolbar does, the format bar takes the trailing half of a phone on its side, and
    /// the lines' starts stay in view beside it.
    @Test func theFormatBarTakesTheTrailingHalfOnItsSide() {
        let (pager, window) = pager(on: 0)
        let bar = FormatBar.shared
        bar.layoutIfNeeded()
        #expect(bar.glassFrameForTesting.minX < 20)
        // A window wider than it's tall is short: its size class is compact.
        turn(pager.container, to: Self.onItsSide, in: window)
        bar.layoutIfNeeded()
        #expect(abs(bar.glassFrameForTesting.minX - bar.bounds.midX) < 1)
        #expect(bar.glassFrameForTesting.maxX > bar.bounds.maxX - 20)
    }

    /// Turning upright, the keys for the new way up come a moment into the turn, outside its
    /// animation. The format bar's track keeps the turn's animation, which carries it with the
    /// bottom of the screen: put straight where it ends, it went below the bottom for the turn.
    @Test func theFormatBarTurnsWithTheKeys() {
        let (pager, window) = pager(on: 0)
        let container = pager.container
        pager.controllers[0].focus()
        container.keysForTesting = 180
        turn(container, to: Self.onItsSide, in: window)
        UIView.animate(withDuration: 0.3) {
            window.frame = Self.upright
            container.frame = window.bounds
            container.layoutIfNeeded()
        }
        #expect(container.barTrackIsMovingForTesting)
        container.keysForTesting = 320
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(container.barTrackIsMovingForTesting)
        #expect(container.barTrackFrameForTesting.maxY == Self.upright.height - 320)
    }

    /// Turning upright, UIKit also says the keys are going, and they can read nothing for a moment
    /// before they're back for the new way up: the bar stays on them.
    @Test func theFormatBarStaysOnTheKeysAsTheyTurnUpright() {
        let (pager, window) = pager(on: 0)
        let container = pager.container
        pager.controllers[0].focus()
        container.keysForTesting = 180
        turn(container, to: Self.onItsSide, in: window)
        let left = container.timesBarLeftKeysForTesting
        turn(container, to: Self.upright, in: window)
        container.keyboardWillHideForTesting()
        container.keysForTesting = 0
        container.setNeedsLayout()
        container.layoutIfNeeded()
        container.keysForTesting = 320
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(container.timesBarLeftKeysForTesting == left)
        #expect(container.barTrackFrameForTesting.maxY == Self.upright.height - 320)
    }

    /// Where the system puts a navigation bar's buttons, measured on the iPhone 17, Air and 17e.
    @Test func theDotBarSitsWhereANavigationBarsButtonsDo() {
        let iPhone17 = TopBarPlacement(safeTop: 62, safeSides: 0, width: 402)
        #expect(iPhone17.top == 62 && iPhone17.side == 16)
        let air = TopBarPlacement(safeTop: 68, safeSides: 0, width: 420)
        #expect(air.top == 68 && air.side == 20)
        let onItsSide = TopBarPlacement(safeTop: 0, safeSides: 62, width: 912)
        #expect(onItsSide.top == 24 && onItsSide.side == 38)
    }
}
