import SwiftUI
import OSLog
import UIKit

@main
struct BiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: DotStore
    @State private var sync: PageSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = DotStore()
        let sync = PageSync(store: store)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        PageSync.shared = sync
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            sync.isOnScreen = phase == .active
            if phase == .background {
                sync.sendBeforeLeaving()
                if PageSync.runsHere { BackgroundSync.schedule() }
            }
        }
    }
}

/// Starts syncing as Bite launches, also when a push or a background refresh launches it in the
/// background, and hands iCloud's pushes to the sync.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if PageSync.runsHere {
            BackgroundSync.register()
            PageSync.shared?.start()
            // iCloud's pushes, which bring other devices' changes, come as notifications.
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PageSync.log.info("Registered for iCloud's pushes")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PageSync.log.error("Couldn't register for iCloud's pushes: \(error.localizedDescription)")
    }

    /// Whether a page came in, which the system goes by to wake Bite for pushes as often as is
    /// useful.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PageSync.shared?.pushArrived() == true ? .newData : .noData
    }
}
