import Foundation
import Testing
import BiteKit
@testable import Bite

/// A to-do ticked in a phone's widget, which the system runs in Bite (see `ToggleToDoIntent`).
@MainActor
struct WidgetTicksInBiteTests {
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
}
