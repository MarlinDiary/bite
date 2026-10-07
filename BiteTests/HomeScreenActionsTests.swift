import Testing
import UIKit
import BiteKit
@testable import Bite

/// Bite's icon on the Home Screen, touched and held, offers to keep writing, or add a to-do, on the
/// page Bite was last on.
@MainActor
struct HomeScreenActionsTests {
    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteHomeScreenTests-\(UUID().uuidString)"))
    }

    @Test func theyreForThePageBiteWasLastOn() {
        let items = HomeScreenActions.items(for: 3)
        #expect(items.map(\.type) == [HomeScreenActions.keepWriting, HomeScreenActions.addToDo])
        #expect(items.map(\.localizedTitle) == ["Keep Writing", "Add To-Do"])
        #expect(items.map(\.localizedSubtitle) == ["Purple", "Purple"])

        let store = store()
        store.selection = 5
        HomeScreenActions.update(for: store)
        #expect(UIApplication.shared.shortcutItems?.map(\.localizedSubtitle) == ["Teal", "Teal"])
    }

    /// Picked as it launches Bite, the line waits for the pages to be there.
    @Test func onePickedAsBiteLaunchesWaitsForThePages() {
        let store = store()
        store.selection = 0
        #expect(HomeScreenActions.perform(HomeScreenActions.items(for: 4)[1], in: store))
        #expect(store.selection == 4)
        var started: [(dot: Int, asToDo: Bool)] = []
        store.startLineInEditor = { started.append(($0, $1)) }
        #expect(started.count == 1)
        #expect(started.first?.dot == 4 && started.first?.asToDo == true)
        let other = UIApplicationShortcutItem(type: "com.example.other", localizedTitle: "Other")
        #expect(!HomeScreenActions.perform(other, in: store))
        #expect(started.count == 1)
    }

    /// In the pager, the page comes on with its line started and the keyboard on it.
    @Test func thePageComesOnWithItsLineStarted() {
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
        for controller in pager.controllers {
            controller.load(markdown: "Page \(controller.dot)")
        }
        pager.container.layoutIfNeeded()
        pager.scrollView.go(to: 1)

        pager.startLine(on: 6, asToDo: true)
        #expect(pager.scrollView.currentPage == 6)
        let page = pager.controllers[6]
        #expect(page.textView.isFirstResponder)
        #expect(page.textView.selectedRange.location == page.textView.text.count - 1)
        page.textView.insertText("milk")
        #expect(page.markdownForTesting == "Page 6\n- [ ] milk")
        window.isHidden = true
    }
}
