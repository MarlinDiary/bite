import Testing
import UIKit
@testable import Bite

/// The room a page leaves under its text for the keyboard, as a swipe takes the keyboard away.
@MainActor
struct KeyboardRoomTests {
    /// A long page with room for the keyboard, at its top.
    private func pageWithRoom(in editor: EditorHarness) -> BiteTextView {
        let page = EditorController(dot: 1, accent: .systemBlue)
        editor.addPage(page)
        page.load(markdown: (1...80).map { "Line \($0)" }.joined(separator: "\n"))
        page.textView.keepKeyboardRoom()
        page.textView.keyboardOverlap = 336
        page.textView.layoutIfNeeded()
        return page.textView
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Pulled past its top, a page swiped at takes the keyboard away and is let go of there,
    /// springing back. Its room went at once, and UIKit put the page back in range under the
    /// spring: the text dropped and crept back up as the keyboard left.
    @Test func aPageSpringingBackKeepsItsRoomUntilItIsBack() async {
        let editor = EditorHarness("a")
        let view = pageWithRoom(in: editor)
        let withRoom = view.contentInset.bottom
        let top = -view.contentInset.top
        view.contentOffset.y = top - 150
        view.isDeceleratingForTesting = true
        view.keyboardOverlap = 0
        #expect(view.contentInset.bottom == withRoom)
        #expect(view.contentOffset.y == top - 150)
        // Partway back.
        await wait(0.1)
        view.contentOffset.y = top - 40
        await wait(0.1)
        #expect(view.contentInset.bottom == withRoom)
        #expect(view.contentOffset.y == top - 40)
        // Back at the top, and still.
        view.contentOffset.y = top
        view.isDeceleratingForTesting = false
        for _ in 0..<20 where view.contentInset.bottom == withRoom {
            await wait(0.05)
        }
        #expect(view.contentInset.bottom < withRoom)
        #expect(view.contentOffset.y == top)
    }

    /// Gliding to a stop within its range, a page loses its room at once: kept until the page
    /// stopped, the room a swiped-away keyboard left stayed open half a second too long.
    @Test func aPageGlidingWithinItsRangeLosesItsRoomAtOnce() {
        let editor = EditorHarness("a")
        let view = pageWithRoom(in: editor)
        let withRoom = view.contentInset.bottom
        view.contentOffset.y = 300
        view.isDeceleratingForTesting = true
        view.keyboardOverlap = 0
        #expect(view.contentInset.bottom < withRoom)
        #expect(view.contentOffset.y == 300)
        view.isDeceleratingForTesting = nil
    }
}
