import AppKit

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
    private let store = DotStore()
    private var panel: PanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugSnapshot.prepare()
        #endif
        let panel = PanelController(store: store)
        let statusItem = StatusItemController()
        statusItem.onClick = { [weak panel] in panel?.toggle() }
        statusItem.menu = { [weak panel] in panel?.makeMenu() ?? NSMenu() }
        panel.statusItem = statusItem
        self.panel = panel
        self.statusItem = statusItem
        NSApp.mainMenu = MainMenu.make()
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
        SettingsWindowController.shared.show()
    }
}
