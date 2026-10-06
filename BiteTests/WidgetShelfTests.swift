import Foundation
import Testing
import BiteKit
@testable import Bite

/// The copy of the pages Bite keeps for its widgets, which can't read Bite's own files.
@MainActor
struct WidgetShelfTests {
    /// Written as Bite opens, for a widget added before, and again whenever the pages are.
    @Test func theWidgetsCopyFollowsThePages() {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetShelfTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DotStore(folder: root.appending(path: "Dots"))
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        withExtendedLifetime(shelf) {
            #expect(copy.read() == store.markdown)
            store.update(dot: 2, markdown: "- [ ] milk\n")
            #expect(copy.read()?[2] != "- [ ] milk\n")
            store.saveNow()
            #expect(copy.read()?[2] == "- [ ] milk\n")
            #expect(copy.read() == store.markdown)
        }
    }

    /// A to-do ticked in a widget, which the system runs in Bite, goes onto the page at once,
    /// and to disk, before Bite may be stopped again.
    @Test func aTickFromAWidgetGoesOntoThePageAtOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetTakeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = root.appending(path: "Dots")
        let store = DotStore(folder: pages)
        store.update(dot: 1, markdown: "- [ ] tea\n")
        store.saveNow()
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        try withExtendedLifetime(shelf) {
            try copy.leave(PageTick(page: 1, block: 0, text: "tea", done: true))
            ToDoTicks.take()
            #expect(store.markdown[1] == "- [x] tea\n")
            #expect(DotStore(folder: pages).markdown[1] == "- [x] tea\n")
            #expect(copy.read()?[1] == "- [x] tea\n")
        }
    }

    /// To-dos ticked in a widget while Bite wasn't running go onto the page as Bite opens, once,
    /// and the widgets' copy keeps them.
    @Test func toDosTickedInAWidgetGoOntoThePage() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetTicksTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = root.appending(path: "Dots")
        let first = DotStore(folder: pages)
        first.update(dot: 3, markdown: "# Shopping\n- [ ] eggs\n- [x] milk\n")
        first.saveNow()
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        try copy.leave(PageTick(page: 3, block: 1, text: "eggs", done: true))
        try copy.leave(PageTick(page: 3, block: 2, text: "milk", done: false))

        let store = DotStore(folder: pages)
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        withExtendedLifetime(shelf) {
            #expect(store.markdown[3] == "# Shopping\n- [x] eggs\n- [ ] milk\n")
            #expect(DotStore(folder: pages).markdown[3] == store.markdown[3])
            #expect(copy.read()?[3] == store.markdown[3])
            #expect(copy.takeTicks().isEmpty)
        }
    }
}
