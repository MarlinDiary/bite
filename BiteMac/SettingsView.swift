import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// Back to the app that was in use, as Bite has no other window to be in.
    func windowWillClose(_ notification: Notification) {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey && $0 !== window }) {
            NSApp.deactivate()
        }
    }
}

struct SettingsView: View {
    @State private var shortcut = GlobalShortcut.shared.saved
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            LabeledContent("Open Bite") {
                ShortcutRecorder(shortcut: $shortcut)
            }
            Toggle("Open at Login", isOn: $opensAtLogin)
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
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
