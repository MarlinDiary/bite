import AppIntents
import BiteKit
import CoreSpotlight
import SwiftUI
import OSLog
import UIKit

@main
struct BiteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        SceneDelegate.store = store
        // The pages Siri and Shortcuts work on (see `PageIntents`). Asked for the pages each
        // shortcut is shown for, Shortcuts names their groups.
        AppDependencyManager.shared.add(dependency: store)
        BiteShortcuts.updateAppShortcutParameters()
        let spotlight = SpotlightIndex(store: store)
        _spotlight = State(initialValue: spotlight)
        if SpotlightIndex.runsHere { spotlight.start() }
        // Takes in to-dos ticked in widgets since Bite last ran, too.
        _widgets = State(initialValue: WidgetShelf(store: store))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("-glassSwatches") {
                GlassSwatches()
            } else {
                root
            }
            #else
            root
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            sync.isOnScreen = phase == .active
            if phase == .active {
                ScreenChoices.apply()
                // To-dos ticked in a widget while Bite was away.
                widgets.update()
            }
            if phase == .background {
                sync.sendBeforeLeaving()
                if PageSync.runsHere { BackgroundSync.schedule() }
                // For the page Bite was left on.
                HomeScreenActions.update(for: store)
            }
        }
    }

    private var root: some View {
        RootView()
            .environment(store)
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                // Bite launched by it opened it already, before its first frame.
                guard activity !== SceneDelegate.launchActivity else { return }
                SpotlightIndex.open(activity, in: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: Preferences.didChange)) { _ in
                ScreenChoices.apply()
            }
            // A widget, tapped, opens the page it shows.
            .onOpenURL { link in
                if let page = PageTurns.page(openedBy: link) { store.open(dot: page) }
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

    /// Upright only, when Settings says so (see `ScreenChoices`).
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        ScreenChoices.orientations
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Opens Bite at a Spotlight result from its very first frame when Spotlight launches it. SwiftUI
/// hands the result over only once Bite is on screen, and the page Bite was last on showed first,
/// for a few frames. Brought back from the background, SwiftUI's own handover is in time. Takes
/// what's picked from Bite's icon on the Home Screen too (see `HomeScreenActions`).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The app's, which the result is opened in.
    static var store: DotStore?
    /// The result Bite was launched at, until SwiftUI has handed it over too.
    static weak var launchActivity: NSUserActivity?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let store = Self.store else { return }
        for activity in connectionOptions.userActivities where activity.activityType == CSSearchableItemActionType {
            Self.launchActivity = activity
            SpotlightIndex.open(activity, in: store)
        }
        // So is a widget's page, when a tap on the widget launches Bite. SwiftUI hands the link
        // over too, after, to the same page.
        for context in connectionOptions.urlContexts {
            if let page = PageTurns.page(openedBy: context.url) { store.open(dot: page) }
        }
        if let item = connectionOptions.shortcutItem {
            HomeScreenActions.perform(item, in: store)
        }
    }

    /// Picked from Bite's icon with Bite in the background.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let store = Self.store else { return completionHandler(false) }
        completionHandler(HomeScreenActions.perform(shortcutItem, in: store))
    }
}
