import AppKit
import SwiftUI
import ServiceManagement
import BiteKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(store: DotStore) {
        let window = window ?? makeWindow(store: store)
        self.window = window
        if !window.isVisible { centre(window) }
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// In the middle of the screen in use, the one with the pointer, below its menu bar and above
    /// its Dock. AppKit's `center()` puts a window higher than the middle.
    private func centre(_ window: NSWindow) {
        // Sized first: SwiftUI sizes the window only once it's laid out, and centred before, the
        // window's corner went in the middle.
        if let content = window.contentViewController?.view {
            window.setContentSize(content.fittingSize)
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let area = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded()))
    }

    private func makeWindow(store: DotStore) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.level = PanelController.levelAbove
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// Back to the app that was in use, as Bite has no other window to be in. Bite gives it back
    /// by hiding: told to deactivate, it stayed active with nothing on screen.
    func windowWillClose(_ notification: Notification) {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey && $0 !== window }) {
            NSApp.hide(nil)
        }
    }

    #if DEBUG
    func windowForTesting(store: DotStore) -> NSWindow {
        makeWindow(store: store)
    }
    #endif
}

struct SettingsView: View {
    let store: DotStore
    @State private var shortcut = GlobalShortcut.shared.saved
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var syncsWithICloud = Preferences.syncsWithICloud
    @State private var showsInSpotlight = Preferences.showsInSpotlight
    @State private var checksSpelling = Preferences.checksSpelling
    @State private var panelIsGlass = Preferences.panelIsGlass
    @State private var dotGlows = Preferences.dotGlows
    @State private var isConfirmingReset = false
    /// Whether the command for the `bite` tool was copied, which its button says.
    @State private var copiedCommand = false

    /// The switches are in the colour of the page on screen, as the rest of Bite is. The buttons
    /// stay as the Mac's are.
    private var pageColour: Color {
        DotPalette.colors[store.selection].color
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Open Bite") {
                    ShortcutRecorder(shortcut: $shortcut)
                }
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .tint(pageColour)
            }
            Section {
                Toggle("Glass Panel", isOn: $panelIsGlass)
                    .tint(pageColour)
                Toggle("Glowing Dot", isOn: $dotGlows)
                    .tint(pageColour)
                Toggle("Check Spelling", isOn: $checksSpelling)
                    .tint(pageColour)
            }
            Section {
                Toggle("Sync with iCloud", isOn: $syncsWithICloud)
                    .tint(pageColour)
                Toggle("Show in Spotlight", isOn: $showsInSpotlight)
                    .tint(pageColour)
            }
            Section {
                LabeledContent("Command Line Tool") {
                    Button(copiedCommand ? "Copied" : "Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CommandLineTool.installCommand(), forType: .string)
                        copiedCommand = true
                    }
                }
            } footer: {
                Text("Paste it into Terminal. You, or an AI such as Claude Code, can then read and change your pages with bite.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent("Reset All Pages") {
                    Button("Reset…", role: .destructive) {
                        isConfirmingReset = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .alert("Reset all pages?", isPresented: $isConfirmingReset) {
            Button("Reset All Pages", role: .destructive) {
                store.resetAllPages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(PageReset.message)
        }
        .onChange(of: syncsWithICloud) {
            Preferences.syncsWithICloud = syncsWithICloud
        }
        .onChange(of: showsInSpotlight) {
            Preferences.showsInSpotlight = showsInSpotlight
        }
        .onChange(of: checksSpelling) {
            Preferences.checksSpelling = checksSpelling
        }
        .onChange(of: panelIsGlass) {
            Preferences.panelIsGlass = panelIsGlass
        }
        .onChange(of: dotGlows) {
            Preferences.dotGlows = dotGlows
        }
        // Spelling can be turned on and off from the Edit menu too.
        .onReceive(NotificationCenter.default.publisher(for: Preferences.didChange)) { _ in
            checksSpelling = Preferences.checksSpelling
            syncsWithICloud = Preferences.syncsWithICloud
        }
        .onChange(of: shortcut) {
            GlobalShortcut.shared.saved = shortcut
        }
        .onChange(of: opensAtLogin) {
            do {
                if opensAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                opensAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Click, then type the shortcut. Esc cancels; the button beside it clears the shortcut.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Type Shortcut" : shortcut?.title ?? "Record Shortcut") {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 120)
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        GlobalShortcut.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 {
                // Esc
                stopRecording()
            } else if let typed = Shortcut(event) {
                shortcut = typed
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            GlobalShortcut.shared.registerSaved()
        }
    }
}
