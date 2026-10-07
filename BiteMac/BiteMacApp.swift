import AppIntents
import AppKit
import BiteKit
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
    private var widgets: WidgetShelf?

    override init() {
        super.init()
        // The pages Siri and Shortcuts work on (see `PageIntents`). Asked for the pages each
        // shortcut is shown for, Shortcuts names their groups.
        let store = store
        AppDependencyManager.shared.add(dependency: store)
        BiteShortcuts.updateAppShortcutParameters()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.prepare()
        // A snapshot's choices are its own, not for Bite's extensions.
        if !DebugSnapshot.isRequested {
            Preferences.keepCopy(in: UserDefaults(suiteName: PageShelf.appGroup))
        }
        #else
        // For Bite's extensions, which can't read the choices in Settings.
        Preferences.keepCopy(in: UserDefaults(suiteName: PageShelf.appGroup))
        #endif
        let panel = PanelController(store: store)
        let statusItem = StatusItemController()
        statusItem.onClick = { [weak panel] in panel?.toggle() }
        statusItem.menu = { [weak panel] in panel?.makeRingMenu() ?? NSMenu() }
        panel.statusItem = statusItem
        self.panel = panel
        self.statusItem = statusItem
        // The pages for the widgets on the desktop, and the to-dos ticked there while Bite was out.
        widgets = WidgetShelf(store: store, folder: Self.shelfFolder)
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

    /// The folder Bite shares with its extensions and its command line tool. A snapshot's pages
    /// aren't the person's, so it keeps its own: `-snapshotShelf NAME` names one in the shared
    /// folder, for the command line tool to be tried on.
    private static var shelfFolder: URL? {
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup)
        #if DEBUG
        if DebugSnapshot.isRequested {
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "-snapshotShelf"), index + 1 < arguments.count {
                return shared?.appending(path: arguments[index + 1], directoryHint: .isDirectory)
            }
            return FileManager.default.temporaryDirectory.appending(path: "BiteSnapshotShelf-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        #endif
        return shared
    }

    /// A widget clicked on the desktop: the panel comes up on the page it shows.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let page = PageTurns.page(openedBy: url) { store.open(dot: page) }
        }
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
