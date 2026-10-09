import AppKit
import SwiftUI

/// Bite's welcome, the first time it opens on a Mac (see `WelcomeSheet`): a window in the middle of
/// the screen, Bite having no other to show it on. Closed, by Continue or its close button, it goes
/// and the panel comes down from the ring in the menu bar, to show where Bite lives.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?
    private var afterClosing: (() -> Void)?

    func show(then afterClosing: @escaping () -> Void) {
        self.afterClosing = afterClosing
        let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeSheet(onContinue: { [weak self] in
            self?.window?.close()
        })))
        // Its welcome only, as Apple's apps have theirs: no title, the window's controls over the
        // top of it.
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        // Closed, not made small or full screen.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = PanelController.levelAbove
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        window.centreOnScreenInUse()
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        let afterClosing = afterClosing
        self.afterClosing = nil
        // Once it's gone, or the panel would come down behind it.
        DispatchQueue.main.async { afterClosing?() }
    }
}
