import Testing
import UIKit
@testable import Bite

/// With the keyboard up, a page moved to shows up where editing it scrolls to. It used to show
/// up where it was, often the top, and then scroll down to its caret.
@MainActor
struct ArrivingPageTests {
    private func longPage(in editor: EditorHarness) -> EditorController {
        let page = EditorController(dot: 1, accent: .systemBlue)
        page.textView.frame = editor.window.bounds
        editor.window.addSubview(page.textView)
        page.load(markdown: (1...80).map { "Line \($0)" }.joined(separator: "\n"))
        page.textView.keyboardOverlap = 336
        page.textView.layoutIfNeeded()
        return page
    }

    @Test func itArrivesScrolledToItsCaret() async {
        let editor = EditorHarness("a")
        let page = longPage(in: editor)
        #expect(page.textView.contentOffset.y <= 0)
        page.arrive()
        let arrived = page.textView.contentOffset.y
        #expect(arrived > 1000)
        // Taking the keyboard, it doesn't move again.
        page.focus()
        for _ in 0..<10 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.textView.isFirstResponder)
        #expect(abs(page.textView.contentOffset.y - arrived) < 1)
        #expect(page.textView.selectedRange.location == (page.textView.text as NSString).length - 1)
    }

    /// Scrolled by hand before it takes the keyboard, a page stays where it was scrolled to.
    @Test func aPageScrolledBeforeTakingTheKeyboardStaysPut() async {
        let editor = EditorHarness("a")
        let page = longPage(in: editor)
        page.arrive()
        page.textView.contentOffset.y = 300
        page.scrollViewDidEndDragging(page.textView, willDecelerate: false)
        page.focus()
        for _ in 0..<10 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.textView.isFirstResponder)
        #expect(abs(page.textView.contentOffset.y - 300) < 1)
        // Typing brings the caret back into view.
        let caret = page.textView.selectedRange
        if page.textView(page.textView, shouldChangeTextIn: caret, replacementText: "x") {
            page.textView.insertText("x")
        }
        for _ in 0..<10 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(page.textView.contentOffset.y > 1000)
    }

    /// A page readied for a swipe that went the other way stays ready, so the next drag has
    /// nothing to do, until the keyboard goes.
    @Test func aReadyPageStaysReadyUntilTheKeyboardGoes() {
        let editor = EditorHarness("a")
        let page = longPage(in: editor)
        page.arrive()
        let withRoom = page.textView.contentInset.bottom
        let arrived = page.textView.contentOffset.y
        page.textView.keyboardOverlap = 336
        page.textView.layoutIfNeeded()
        #expect(page.textView.keepsKeyboardRoom)
        #expect(page.textView.contentInset.bottom == withRoom)
        #expect(page.textView.contentOffset.y == arrived)
        page.textView.keyboardOverlap = 0
        #expect(!page.textView.keepsKeyboardRoom)
        #expect(page.textView.contentInset.bottom < withRoom)
    }

    /// The page giving the keyboard up to another keeps its room and place, for a swipe back.
    @Test func thePageLeftKeepsItsPlace() async {
        let editor = EditorHarness("a")
        let page = longPage(in: editor)
        page.textView.frame.origin.x = editor.window.bounds.width
        page.arrive()
        page.focus()
        for _ in 0..<5 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        let offset = page.textView.contentOffset.y
        let withRoom = page.textView.contentInset.bottom
        page.textView.keepKeyboardRoom()
        editor.controller.focus()
        #expect(!page.textView.isFirstResponder)
        #expect(page.textView.contentInset.bottom == withRoom)
        #expect(page.textView.contentOffset.y == offset)
    }

    /// Swiped away from and straight back: the page lost its room for the keyboard with an
    /// animation that was still running as it came back, and its text moved as it came in.
    @Test func aPageLeftOffScreenKeepsNothingMoving() async {
        let editor = EditorHarness("a")
        let page = longPage(in: editor)
        // Beside the page on screen, as in the pager.
        page.textView.frame.origin.x = editor.window.bounds.width
        page.focus()
        for _ in 0..<5 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        let withRoom = page.textView.contentInset.bottom
        editor.controller.focus()
        #expect(!page.textView.isFirstResponder)
        #expect(page.textView.contentInset.bottom < withRoom)
        #expect(page.textView.layer.animationKeys()?.isEmpty ?? true)
        page.arrive()
        let arrived = page.textView.contentOffset.y
        #expect(page.textView.layer.animationKeys()?.isEmpty ?? true)
        page.focus()
        for _ in 0..<10 {
            page.textView.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(abs(page.textView.contentOffset.y - arrived) < 1)
    }
}

/// The seven pages in the pager, in a window, with the keyboard on one of them.
@MainActor
private final class PagerHarness {
    let pager = DotPagerCoordinator()
    let window: UIWindow
    var scrollView: PagerScrollView { pager.scrollView }
    var width: CGFloat { scrollView.bounds.width }

    init(editing page: Int) {
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        EditorHarness.show(window)
        for controller in pager.controllers {
            controller.load(markdown: (1...40).map { "Line \($0) of page \(controller.dot)" }.joined(separator: "\n"))
        }
        pager.container.layoutIfNeeded()
        scrollView.go(to: page)
        pager.controllers[page].focus()
    }

    /// The page with the keyboard.
    var editing: Int? { pager.controllers.first { $0.textView.isFirstResponder }?.dot }

    /// A finger lifting from a swipe that sends the pager to `page`.
    func flick(to page: Int) {
        var target = CGPoint(x: CGFloat(page) * width, y: 0)
        pager.scrollViewWillEndDragging(scrollView, withVelocity: CGPoint(x: 2, y: 0), targetContentOffset: &target)
    }

    /// The pager coming to rest, or being stopped, at `x`.
    func stop(at x: CGFloat) {
        scrollView.contentOffset.x = x
        pager.scrollViewDidEndDecelerating(scrollView)
    }

    func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// Passing the keyboard to another page holds everything up for about a tenth of a second.
@MainActor
struct PassingTheKeyboardTests {
    @Test func aSwipeThatLandsPassesTheKeyboardAtOnce() {
        let harness = PagerHarness(editing: 1)
        harness.flick(to: 2)
        #expect(harness.editing == 1)
        harness.stop(at: 2 * harness.width)
        #expect(harness.editing == 2)
    }

    /// Flicked past the first page and caught as it bounced back, the pager stops and says it has
    /// come to rest. Passed right then, under the finger, the keyboard held up the pull it began.
    @Test func thePagerCaughtAsItBouncesKeepsTheKeyboardUntilLetGo() async {
        let harness = PagerHarness(editing: 1)
        harness.flick(to: 0)
        harness.stop(at: -33)
        #expect(harness.editing == 1)
        await harness.wait(0.2)
        #expect(harness.editing == 1)
        // Let go, it springs back onto the page, maybe without saying so.
        harness.scrollView.contentOffset.x = 0
        await harness.wait(0.2)
        #expect(harness.editing == 0)
    }

    @Test func pastTheLastPageToo() async {
        let harness = PagerHarness(editing: 5)
        harness.flick(to: 6)
        harness.stop(at: 6 * harness.width + 40)
        await harness.wait(0.2)
        #expect(harness.editing == 5)
        harness.stop(at: 6 * harness.width)
        #expect(harness.editing == 6)
    }

    /// The keyboard put away while the pager was held stays away.
    @Test func aKeyboardPutAwayMeanwhileStaysAway() async {
        let harness = PagerHarness(editing: 1)
        harness.flick(to: 0)
        harness.stop(at: -33)
        harness.pager.controllers[1].textView.resignFirstResponder()
        harness.stop(at: 0)
        await harness.wait(0.2)
        #expect(harness.editing == nil)
    }

    /// A dot picked while a swipe settles takes the keyboard, and keeps it once the swipe is over.
    @Test func aDotPickedMeanwhileKeepsTheKeyboard() async {
        let harness = PagerHarness(editing: 1)
        harness.flick(to: 0)
        harness.stop(at: -33)
        harness.pager.show(page: 4)
        #expect(harness.editing == 4)
        harness.pager.scrollViewDidEndDecelerating(harness.scrollView)
        await harness.wait(0.2)
        #expect(harness.editing == 4)
    }
}
