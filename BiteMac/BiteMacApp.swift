import AppKit
import OSLog

/// Bite on the Mac lives in the menu bar: a ring there opens the seven dots in a panel below it.
@main
enum BiteMacApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DotStore(folder: AppDelegate.pagesFolder)
    private lazy var sync = PageSync(store: store)
    private lazy var spotlight = SpotlightIndex(store: store)
    private var panel: PanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.prepare()
        #endif
        let panel = PanelController(store: store)
        let statusItem = StatusItemController()
        statusItem.onClick = { [weak panel] in panel?.toggle() }
        statusItem.menu = { [weak panel] in panel?.makeRingMenu() ?? NSMenu() }
        panel.statusItem = statusItem
        self.panel = panel
        self.statusItem = statusItem
        NSApp.mainMenu = MainMenu.make()
        if PageSync.runsHere {
            sync.start()
            // iCloud's pushes, which bring other devices' changes, come as notifications.
            NSApp.registerForRemoteNotifications()
            // iCloud's pushes come late or not at all, so while the panel is up it asks.
            panel.onVisibleChange = { [weak self] visible in self?.sync.isOnScreen = visible }
        }
        if SpotlightIndex.runsHere {
            spotlight.start()
        }
        GlobalShortcut.shared.onPress = { [weak panel] in panel?.toggle() }
        GlobalShortcut.shared.registerSaved()
        // Opened for the first time, it shows where it went.
        if !UserDefaults.standard.bool(forKey: Self.hasOpenedKey) {
            UserDefaults.standard.set(true, forKey: Self.hasOpenedKey)
            panel.showOnceRingIsPlaced()
        }
        #if DEBUG
        if DebugSnapshot.isRequested {
            DebugSnapshot.run(panel: panel, store: store)
        }
        #endif
    }

    private static let hasOpenedKey = "hasOpenedPanel"

    /// Launched to take pictures of itself, the app keeps pages of its own, the first-launch ones,
    /// away from the person's.
    private static var pagesFolder: URL {
        #if DEBUG
        if DebugSnapshot.isRequested {
            return FileManager.default.temporaryDirectory.appending(path: "BiteSnapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        #endif
        return DotStore.defaultFolder
    }

    /// A page picked in Spotlight (see `SpotlightIndex`).
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        SpotlightIndex.open(userActivity, in: store)
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PageSync.log.info("Registered for iCloud's pushes")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PageSync.log.error("Couldn't register for iCloud's pushes: \(error.localizedDescription)")
    }

    /// A push from iCloud, as another device changed a page: brought down at once.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { await sync.pushArrived() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Opened again while running, from Finder or Spotlight: the panel comes up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }

    @objc func showSettings(_ sender: Any?) {
        panel?.hideForOtherWindow()
        SettingsWindowController.shared.show(store: store)
    }
}
