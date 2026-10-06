import Foundation
import WidgetKit
import BiteKit

/// Keeps Bite's widgets showing the pages as they are: a copy of every page where the widgets can
/// read it (see `PageShelf`), written as the pages are, and the widgets told to look again.
@MainActor
final class WidgetShelf {
    private let store: DotStore
    private let shelf: PageShelf?

    init(store: DotStore, folder: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup)) {
        self.store = store
        shelf = folder.map(PageShelf.init(folder:))
        store.onSaveForWidgets = { [weak self] in self?.update() }
        // A to-do ticked in a widget, which the system runs in Bite: onto the page now, and, with
        // Bite off screen, up to iCloud before the system stops it again.
        ToDoTicks.taker = { [weak self] in
            self?.update()
            PageIntents.sendIfOffScreen()
        }
        // The pages as they are as Bite opens, which a widget added before then has no copy of.
        update()
    }

    /// Writes the pages, if they're not as last written, and has the widgets read them again. To-dos
    /// ticked in a widget while Bite wasn't there to take them go in first, so the copy keeps them.
    func update() {
        takeTicks()
        guard let shelf, shelf.read() != store.markdown, (try? shelf.write(store.markdown)) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var isTakingTicks = false

    /// The to-dos ticked in widgets since Bite last ran, onto the pages as if ticked here.
    private func takeTicks() {
        guard let shelf, !isTakingTicks else { return }
        isTakingTicks = true
        defer { isTakingTicks = false }
        for tick in shelf.takeTicks() {
            store.tick(tick)
        }
    }
}
