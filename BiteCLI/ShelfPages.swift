import AppKit
import BiteCommands
import BiteKit

/// Bite's pages through the folder Bite shares with its extensions (see `PageShelf`): read from the
/// copy Bite keeps there, and changed by leaving each change there for Bite to take in, as Bite's
/// share extension does. A Bite not running is started for it.
struct ShelfPages: PageAccess {
    private let shelf: PageShelf?
    /// Bite on the Mac.
    private static let bite = "com.chenyeni.bite"

    init() {
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup)
        #if DEBUG
        // `BITE_SHELF=NAME` tries the tool on a Bite started with `-snapshot -snapshotShelf NAME`,
        // whose pages are its own, never the person's.
        if let name = ProcessInfo.processInfo.environment["BITE_SHELF"] {
            shelf = shared.map { PageShelf(folder: $0.appending(path: name, directoryHint: .isDirectory)) }
            return
        }
        #endif
        shelf = shared.map(PageShelf.init(folder:))
    }

    func pages() async throws -> [String] {
        let shelf = try reachable()
        if let pages = shelf.read() { return pages }
        // Bite writes them as it starts.
        if await start() {
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(100))
                if let pages = shelf.read() { return pages }
            }
        }
        throw CommandError("Bite hasn't kept its pages where the tool can read them yet: open Bite, then try again.")
    }

    func modified() async -> [Date?] {
        shelf?.readModified() ?? []
    }

    func shownPage() async -> Int? {
        shelf?.readLastPage()
    }

    func change(page: Int, from before: String, to after: String) async throws -> String? {
        let shelf = try reachable()
        let file = try shelf.leave(PageShare(page: page, before: before, after: after))
        DistributedNotificationCenter.default().postNotificationName(PageShelf.sharesLeft, object: nil, userInfo: nil, deliverImmediately: true)
        let started = await start()
        // Taken in once Bite has deleted the file it was left in: later from a Bite just started.
        let deadline = ContinuousClock.now + .seconds(started ? 15 : 5)
        while FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            guard ContinuousClock.now < deadline else { return nil }
            try await Task.sleep(for: .milliseconds(25))
        }
        // Then written back where the tool reads the pages.
        let written = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < written {
            if let pages = shelf.read(), pages.indices.contains(page), pages[page] != before { return pages[page] }
            try await Task.sleep(for: .milliseconds(25))
        }
        return shelf.read().flatMap { $0.indices.contains(page) ? $0[page] : nil }
    }

    func open(page: Int) async throws {
        #if DEBUG
        // The Mac sends a page's link to the Bite in use, whichever Bite is asked.
        if ProcessInfo.processInfo.environment["BITE_SHELF"] != nil { throw CommandError("A test shelf's Bite can't be sent a page to show.") }
        #endif
        guard let app = Self.app else { throw CommandError("Bite can't be found, to show the page.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([PageTurns.link(to: page)], withApplicationAt: app, configuration: configuration)
    }

    private func reachable() throws -> PageShelf {
        guard let shelf else { throw CommandError("Bite's pages can't be reached from here: use the bite inside Bite.app.") }
        return shelf
    }

    /// Starts Bite in the background if it isn't running, saying whether it did.
    private func start() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BITE_SHELF"] != nil { return false }
        #endif
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.bite).isEmpty, let app = Self.app else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        return (try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)) != nil
    }

    /// The version of the Bite the tool came in.
    static var biteVersion: String? {
        app.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    }

    /// The Bite the tool came in, it being at Bite.app/Contents/Helpers/bite, or else the one the
    /// Mac knows.
    private static var app: URL? {
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == bite { return app }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bite)
    }
}
