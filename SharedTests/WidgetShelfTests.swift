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

    /// A page shared to while Bite wasn't running goes in as Bite opens, once, onto the page as it
    /// is, and the widgets' copy keeps it.
    @Test func pagesSharedToGoInAsBiteOpens() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetAdditionsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = root.appending(path: "Dots")
        let first = DotStore(folder: pages)
        first.update(dot: 4, markdown: "# Reading\n- [ ] a book\n")
        first.update(dot: 5, markdown: "Notes\n")
        first.saveNow()
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        try copy.leave(PageShare(page: 4, before: "# Reading\n- [ ] a book\n",
                                 after: "# Reading\n- [ ] a book\n- [ ] [A site](https://example.com)\n"))
        // Changed in Bite since the extension read it: both changes are kept.
        try copy.leave(PageShare(page: 5, before: "Note\n", after: "Note\nmore notes\n"))

        let store = DotStore(folder: pages)
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        withExtendedLifetime(shelf) {
            #expect(store.markdown[4] == "# Reading\n- [ ] a book\n- [ ] [A site](https://example.com)\n")
            #expect(store.markdown[5] == "Notes\nmore notes\n")
            #expect(DotStore(folder: pages).markdown[5] == store.markdown[5])
            #expect(copy.read()?[4] == store.markdown[4])
            #expect(copy.takeShares().isEmpty)
        }
    }

    /// Where Bite's share extension opens: the page Bite was last on, from as Bite opens.
    @Test func thePageLastOnIsWhereSharingOpens() {
        let root = FileManager.default.temporaryDirectory.appending(path: "LastPageTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DotStore(folder: root.appending(path: "Dots"))
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        withExtendedLifetime(shelf) {
            #expect(copy.readLastPage() == store.selection)
            store.selection = 2
            store.selection = 6
            #expect(copy.readLastPage() == 6)
        }
    }

    #if os(macOS)
    /// A page shared to on the Mac, where Bite is running in the menu bar, goes in at once.
    @Test func aPageSharedToOnTheMacGoesInAtOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetSharedTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DotStore(folder: root.appending(path: "Dots"))
        store.update(dot: 1, markdown: "Ideas\n")
        store.saveNow()
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        try copy.leave(PageShare(page: 1, before: "Ideas\n", after: "Ideas\nanother\n"))
        DistributedNotificationCenter.default().postNotificationName(PageShelf.sharesLeft, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        for _ in 0..<100 where store.markdown[1] != "Ideas\nanother\n" {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.markdown[1] == "Ideas\nanother\n")
        withExtendedLifetime(shelf) {}
    }

    /// A widget on the Mac's desktop ticks a to-do in its own process and says so: Bite, running
    /// in the menu bar, takes it onto the page at once.
    @Test func aTickSaidByAWidgetIsTakenAtOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "WidgetSaidTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DotStore(folder: root.appending(path: "Dots"))
        store.update(dot: 1, markdown: "- [ ] tea\n")
        store.saveNow()
        let copy = PageShelf(folder: root.appending(path: "Shelf"))
        let shelf = WidgetShelf(store: store, folder: copy.folder)
        try copy.leave(PageTick(page: 1, block: 0, text: "tea", done: true))
        DistributedNotificationCenter.default().postNotificationName(PageShelf.ticksLeft, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
        for _ in 0..<100 where store.markdown[1] != "- [x] tea\n" {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.markdown[1] == "- [x] tea\n")
        withExtendedLifetime(shelf) {}
    }
    #endif
}
