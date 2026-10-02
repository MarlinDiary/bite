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

    /// A long page being edited, its caret at the end, over keys and a format bar 408 points tall,
    /// with the page scrolled to the caret.
    private func pageBeingEdited() async -> EditorHarness {
        let editor = EditorHarness((1...80).map { "Line \($0)" }.joined(separator: "\n"))
        // Laid out in full, so the caret is where it really is, not where TextKit guesses.
        if let layoutManager = editor.textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        editor.textView.keyboardOverlap = 408
        await settle(editor.textView)
        return editor
    }

    /// Waits for the page to stop scrolling to its caret.
    private func settle(_ view: BiteTextView) async {
        var last = CGFloat.nan
        var still = 0
        for _ in 0..<60 where still < 4 {
            view.layoutIfNeeded()
            await wait(0.05)
            still = abs(view.contentOffset.y - last) < 0.5 ? still + 1 : 0
            last = view.contentOffset.y
        }
    }

    /// Writing Tools puts its panel where the keys were, and brings them back once it's done. The
    /// text stays where it was all the while: it moved down as the keys went, and coming back it
    /// jumped, held up by Writing Tools as it finished.
    @Test func theTextStaysPutWhileWritingToolsWorks() async {
        let editor = await pageBeingEdited()
        let view = editor.textView
        let room = view.contentInset.bottom
        let offset = view.contentOffset.y
        #expect(offset > 1000)

        // The keys go, and Writing Tools says it's starting a moment later.
        view.keyboardOverlap = 0
        #expect(view.contentInset.bottom == room)
        await wait(0.1)
        editor.controller.textViewWritingToolsWillBegin(view)
        view.keyboardOverlap = 201
        await wait(0.4)
        #expect(view.contentInset.bottom == room)
        #expect(view.contentOffset.y == offset)

        editor.controller.textViewWritingToolsDidEnd(view)
        view.keyboardOverlap = 408
        await settle(view)
        #expect(view.contentInset.bottom == room)
        #expect(view.contentOffset.y == offset)
    }

    /// Keys that go for anything else, such as a keyboard being connected, give their room back
    /// a moment later.
    @Test func keysGoneOtherwiseGiveTheirRoomBack() async {
        let editor = await pageBeingEdited()
        let view = editor.textView
        let room = view.contentInset.bottom
        view.keyboardOverlap = 0
        #expect(view.contentInset.bottom == room)
        for _ in 0..<20 where view.contentInset.bottom == room {
            await wait(0.05)
        }
        #expect(view.contentInset.bottom < room)
    }
}

