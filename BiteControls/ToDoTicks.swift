import AppIntents
import Foundation
import OSLog
import BiteKit

/// Ticks a to-do off, or on again, from a widget, without opening Bite. On the phone it runs in
/// Bite, started out of sight if it isn't running, as a Live Activity's buttons do: on the widgets'
/// copy of the page first, which they show it by, then onto the page itself and up to iCloud at
/// once (see `WidgetShelf`). Run in the widgets' own process, the tick waited for Bite to be
/// opened before it reached the page, or iCloud. The Mac runs it in the widgets' process, which
/// tells Bite, in the menu bar, to take it.
struct ToggleToDoIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick Off To-Do"
    static let isDiscoverable = false

    @Parameter(title: "Page")
    var page: Int

    @Parameter(title: "Line")
    var block: Int

    @Parameter(title: "To-Do")
    var text: String

    @Parameter(title: "Done")
    var done: Bool

    init() {}

    init(_ tick: PageTick) {
        page = tick.page
        block = tick.block
        text = tick.text
        done = tick.done
    }

    func perform() async throws -> some IntentResult {
        ToDoTicks.leave(PageTick(page: page, block: block, text: text, done: done))
        await ToDoTicks.take()
        return .result()
    }
}

#if os(iOS)
extension ToggleToDoIntent: LiveActivityIntent {}
#endif

nonisolated enum ToDoTicks {
    static let log = Logger(subsystem: "com.chenyeni.bite", category: "widgets")

    /// What Bite does with ticks left on the shelf, set as it starts: takes them onto the pages and
    /// sends the pages up. Not set where only the widgets run, where they wait for Bite.
    @MainActor static var taker: (@MainActor () -> Void)?

    @MainActor static func take() {
        taker?()
    }

    /// The tick onto the widgets' copy of its page, and onto the shelf for Bite.
    static func leave(_ tick: PageTick) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup) else { return }
        let shelf = PageShelf(folder: folder)
        #if os(macOS)
        defer {
            DistributedNotificationCenter.default().postNotificationName(PageShelf.ticksLeft, object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
        }
        #endif
        try? shelf.leave(tick)
        try? shelf.noteShown(tick)
        log.info("Ticked in a widget: page \(tick.page), line \(tick.block), done \(tick.done)")
        guard var pages = shelf.read(), pages.indices.contains(tick.page),
              let page = PageToDos.markdown(pages[tick.page], ticking: tick) else { return }
        pages[tick.page] = page
        try? shelf.write(pages)
    }
}
