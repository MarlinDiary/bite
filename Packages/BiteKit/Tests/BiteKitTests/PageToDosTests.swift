import Foundation
import Testing
@testable import BiteKit

/// To-dos ticked off from a widget, found on the page as it is by then.
struct PageToDosTests {
    private func tick(_ block: Int, _ text: String, done: Bool = true) -> PageTick {
        PageTick(page: 0, block: block, text: text, done: done)
    }

    @Test func aToDoIsTickedOffAndOnAgain() {
        let page = "# Shopping\n- [ ] eggs\n- [ ] milk\n"
        let ticked = PageToDos.markdown(page, ticking: tick(2, "milk"))
        #expect(ticked == "# Shopping\n- [ ] eggs\n- [x] milk\n")
        #expect(ticked.flatMap { PageToDos.markdown($0, ticking: tick(2, "milk", done: false)) } == page)
    }

    /// Ticked as it already is, the page stays as it was.
    @Test func tickingTwiceChangesNothing() {
        let page = "- [x] eggs\n"
        #expect(PageToDos.markdown(page, ticking: tick(0, "eggs")) == page)
    }

    /// Lines added above it since the widget showed it: the to-do is found by its text, the one
    /// nearest where it was.
    @Test func itsFoundWhereThePageHasMovedIt() {
        let page = "New line\n- [ ] milk\n# Later\n- [ ] milk\n"
        #expect(PageToDos.markdown(page, ticking: tick(0, "milk")) == "New line\n- [x] milk\n# Later\n- [ ] milk\n")
        #expect(PageToDos.markdown(page, ticking: tick(3, "milk")) == "New line\n- [ ] milk\n# Later\n- [x] milk\n")
        #expect(PageToDos.markdown("- [ ] tea\n", ticking: tick(0, "milk")) == nil)
        #expect(PageToDos.markdown("milk\n", ticking: tick(0, "milk")) == nil)
    }

    /// Glance lines know where they are on the page, empty lines counted.
    @Test func glanceLinesKnowTheirPlace() {
        let glance = PageGlance(markdown: "# Title\n\n\n- [ ] eggs\n")
        #expect(glance.lines.map(\.block) == [0, 1, 3])
        #expect(glance.withoutTitle().lines.map(\.text) == ["eggs"])
        #expect(PageGlance(markdown: "Plain\n- [ ] a").withoutTitle().lines.count == 2)
    }

    /// Left by a widget, taken by Bite once, in order.
    @Test func ticksWaitOnTheShelfForBite() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PageTicks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let shelf = PageShelf(folder: folder)
        #expect(shelf.takeTicks().isEmpty)
        try shelf.leave(tick(1, "a"))
        try shelf.leave(tick(2, "b", done: false))
        #expect(shelf.takeTicks() == [tick(1, "a"), tick(2, "b", done: false)])
        #expect(shelf.takeTicks().isEmpty)
    }

    /// Ticks made in widgets are kept a minute, for a widget to show a to-do ticked off a moment.
    @Test func shownTicksAreKeptAMinute() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PageShown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let shelf = PageShelf(folder: folder)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        try shelf.noteShown(tick(1, "a"), at: start)
        try shelf.noteShown(tick(2, "b"), at: start.addingTimeInterval(30))
        #expect(shelf.shownTicks(since: start).map(\.tick) == [tick(1, "a"), tick(2, "b")])
        #expect(shelf.shownTicks(since: start.addingTimeInterval(10)).map(\.tick) == [tick(2, "b")])
        // A minute on, the first is let go.
        try shelf.noteShown(tick(3, "c"), at: start.addingTimeInterval(70))
        #expect(shelf.shownTicks(since: .distantPast).map(\.tick) == [tick(2, "b"), tick(3, "c")])
    }
}
