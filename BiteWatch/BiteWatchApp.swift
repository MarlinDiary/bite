import OSLog
import SwiftUI
import WatchKit
import BiteKit

/// Bite on the wrist: the seven pages to look at, tick off and add a line to, the same as on the
/// person's other devices through iCloud, on its own when the phone's away.
@main
struct BiteWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var store: DotStore
    @State private var sync: PageSync
    @State private var widgets: WidgetShelf
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = DotStore()
        let sync = PageSync(store: store)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        PageSync.shared = sync
        // The pages for Bite's widgets on the watch face, written as the pages are.
        _widgets = State(initialValue: WidgetShelf(store: store))
    }

    var body: some Scene {
        WindowGroup {
            PagesView()
                .environment(store)
        }
        .onChange(of: scenePhase, initial: true) { oldPhase, phase in
            // While it's on the wrist and looked at, other devices' changes come in at once.
            sync.isOnScreen = phase == .active
            if phase != .active { store.saveNow() }
            // A to-do ticked or a line added as the wrist went down: not as Bite starts, before
            // it's first on screen.
            if oldPhase == .active, phase != .active { sync.sendBeforeLeaving() }
            if phase == .background, PageSync.runsHere { BackgroundSync.schedule() }
        }
        .backgroundTask(.appRefresh(BackgroundSync.refreshID)) { _ in
            await BackgroundSync.run()
        }
    }
}

/// Starts syncing as Bite launches on the watch, also when a push or a background refresh
/// launches it off screen, and hands iCloud's pushes to the sync.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        guard PageSync.runsHere else { return }
        PageSync.shared?.start()
        // iCloud's pushes, which bring other devices' changes, come as notifications.
        WKApplication.shared().registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        PageSync.log.info("Registered for iCloud's pushes")
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: any Error) {
        PageSync.log.error("Couldn't register for iCloud's pushes: \(error.localizedDescription)")
    }

    /// Whether a page came in, which the system goes by to wake Bite for pushes as often as is
    /// useful.
    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        await PageSync.shared?.pushArrived() == true ? .newData : .noData
    }
}
