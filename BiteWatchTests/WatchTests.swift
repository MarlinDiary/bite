import Foundation
import Testing
import BiteKit
@testable import BiteWatch

/// What the watch app has to tell the system for its background sync and its widgets' links: left
/// out, iCloud's pushes and the background refresh never reach Bite, and a widget opens nothing.
struct WatchSetupTests {
    @Test func iCloudsPushesWakeBite() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("remote-notification") == true)
    }

    /// Not named there, the refresh's handler is turned down as Bite starts.
    @Test func theBackgroundRefreshIsNamedForTheSystem() {
        let names = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(names == [BackgroundSync.refreshID])
    }

    @Test func aWidgetsLinkOpensBite() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes?.contains(PageTurns.scheme) == true)
    }

    @Test func sendingOffScreenFitsTheWatchsFewSeconds() {
        #expect(PageSync.backgroundSendTime == .seconds(10))
    }

    /// A new watch's pages are iCloud's: samples of its own would be merged into them.
    @Test func pagesStartEmpty() {
        for dot in DotPalette.colors.indices {
            #expect(SampleContent.markdown(for: dot).isEmpty)
        }
    }
}

/// The copy of the pages that Bite's widgets on the watch face read.
struct WatchWidgetShelfTests {
    @Test func theCopyFollowsThePages() {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DotStore(folder: folder.appending(path: "Dots"))
        let widgets = WidgetShelf(store: store, folder: folder.appending(path: "Shelf"))
        store.add("Oat milk", asToDo: true, to: 1)
        store.saveNow()
        #expect(PageShelf(folder: folder.appending(path: "Shelf")).read() == store.markdown)
        #expect(store.markdown[1].contains("- [ ] Oat milk"))
        withExtendedLifetime(widgets) {}
    }
}
