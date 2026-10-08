import Testing
import UIKit
import BiteKit
@testable import Bite

/// Bite's windows on an iPad, several at once, each with a page of its own, on one store.
@MainActor @Suite(.serialized)
struct WindowTests {
    private struct OpenWindow {
        let model: PageWindow
        let pager: DotPagerCoordinator
        let window: UIWindow

        var page: EditorController { pager.controllers[model.page] }
    }

    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteWindowTests-\(UUID().uuidString)"))
    }

    /// A window of Bite's on `page`, its pages on `store`, as a window's pager is made.
    private func open(on page: Int, _ store: DotStore) -> OpenWindow {
        let frame = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.frame = frame
        window.traitOverrides.userInterfaceIdiom = .pad
        let model = PageWindow(page: page)
        let pager = DotPagerCoordinator()
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        EditorHarness.show(window)
        pager.connect(to: store, in: model)
        pager.container.layoutIfNeeded()
        return OpenWindow(model: model, pager: pager, window: window)
    }

    /// Types at the end of `page`'s first line, as the keys do.
    private func type(_ text: String, on page: EditorController) {
        let textView = page.textView
        textView.selectedRange = NSRange(location: max(0, (textView.text as NSString).length - 1), length: 0)
        for character in text {
            if page.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: String(character)) {
                textView.insertText(String(character))
            }
        }
    }

    /// The same page in two windows shows the same: what's typed in one comes up in the other as
    /// it's reported, as another device's typing does.
    @Test func typingShowsInAnotherWindowOnThePage() {
        let store = store()
        store.update(dot: 0, markdown: "Hello\n")
        let one = open(on: 0, store)
        let two = open(on: 0, store)
        type(" there", on: one.page)
        one.page.reportPendingChange()
        #expect(store.markdown[0] == "Hello there\n")
        #expect(two.page.markdownForTesting == "Hello there")
        // And back.
        type("!", on: two.page)
        two.page.reportPendingChange()
        #expect(one.page.markdownForTesting == "Hello there!")
        one.window.isHidden = true
        two.window.isHidden = true
    }

    /// Typing not reported yet goes to the other windows as another one's put to use: it would be
    /// left out of what's typed there.
    @Test func typingGoesOverAsAnotherWindowIsUsed() {
        let store = store()
        store.update(dot: 0, markdown: "Hello\n")
        let one = open(on: 0, store)
        let two = open(on: 0, store)
        PageWindows.shared.makeCurrent(one.model)
        type(" there", on: one.page)
        #expect(two.page.markdownForTesting == "Hello")
        PageWindows.shared.pagerWasUsed(two.pager)
        #expect(two.page.markdownForTesting == "Hello there")
        one.window.isHidden = true
        two.window.isHidden = true
    }

    /// Each window shows a page of its own. A page opened from elsewhere, as from a widget or
    /// Siri, opens in the window in front, which is the page Bite's on.
    @Test func eachWindowHasAPageOfItsOwn() {
        let store = store()
        let one = open(on: 0, store)
        let two = open(on: 0, store)
        two.model.page = 2
        #expect(one.model.page == 0)
        PageWindows.shared.makeCurrent(two.model)
        #expect(store.selection == 2)
        store.open(dot: 4)
        #expect(two.model.page == 4)
        #expect(one.model.page == 0)
        PageWindows.shared.makeCurrent(one.model)
        #expect(store.selection == 0)
        one.window.isHidden = true
        two.window.isHidden = true
    }

    /// ⌘F finds on the page on screen, typed in or not, in the system's find bar.
    @Test func findWorksOnThePageOnScreen() {
        let store = store()
        store.update(dot: 1, markdown: "Some words to find\n")
        let one = open(on: 1, store)
        #expect(one.page.textView.isFindInteractionEnabled)
        // Use Selection for Find took ⌘E, which is Code's.
        #expect(!one.page.textView.canPerformAction(#selector(UIResponderStandardEditActions.useSelectionForFind(_:)), withSender: nil))
        one.model.find()
        #expect(one.page.textView.findInteraction?.isFindNavigatorVisible == true)
        one.page.textView.findInteraction?.dismissFindNavigator()
        one.window.isHidden = true
    }
}
