import AppIntents
import OSLog
import SwiftUI
import UIKit
import BiteKit

/// Bite on Apple Vision Pro: the seven pages in a window of glass, picked from the column of dots
/// down its side, the same as on the person's other devices through iCloud.
@main
struct BiteVisionApp: App {
    @UIApplicationDelegateAdaptor(VisionAppDelegate.self) private var appDelegate
    @State private var store: DotStore
    @State private var sync: PageSync
    @State private var spotlight: SpotlightIndex
    @State private var widgets: WidgetShelf
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = DotStore()
        let sync = PageSync(store: store)
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        PageSync.shared = sync
        // The pages Siri and Shortcuts work on (see `PageIntents`), as on the phone.
        AppDependencyManager.shared.add(dependency: store)
        BiteShortcuts.updateAppShortcutParameters()
        let spotlight = SpotlightIndex(store: store)
        _spotlight = State(initialValue: spotlight)
        if SpotlightIndex.runsHere { spotlight.start() }
        // The pages for the widgets in the room, which take in to-dos ticked in them since Bite
        // last ran, too.
        _widgets = State(initialValue: WidgetShelf(store: store))
    }

    var body: some Scene {
        Window("Bite", id: "pages") {
            VisionPages()
                .environment(store)
        }
        // Wider than tall, as visionOS's windows are: the eyes and head move less across than up
        // and down (user, 2026-10-09). The lines keep to a readable measure in the middle (see
        // `BiteTextView.widestText`), the window's glass either side.
        .defaultSize(width: 960, height: 640)
        .onChange(of: scenePhase, initial: true) { _, phase in
            sync.isOnScreen = phase == .active
            if phase == .active {
                // To-dos ticked in a widget while Bite was away.
                widgets.update()
            } else {
                store.saveNow()
            }
        }
    }
}

/// Starts syncing as Bite launches, and hands iCloud's pushes to the sync.
final class VisionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if PageSync.runsHere {
            PageSync.shared?.start()
            // iCloud's pushes, which bring other devices' changes, come as notifications.
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PageSync.log.info("Registered for iCloud's pushes")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PageSync.log.error("Couldn't register for iCloud's pushes: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PageSync.shared?.pushArrived() == true ? .newData : .noData
    }
}
