import AppKit
import Carbon.HIToolbox

/// A key combination that opens the panel from any app, set in Settings. There is none until
/// one is set, so Bite never takes one another app uses.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon's modifier flags (`cmdKey`, `optionKey` and so on).
    var modifiers: UInt32
    /// How the shortcut reads, as menus write it: ⌥⌘B.
    var title: String

    /// The shortcut for a key press, if it holds a modifier other than Shift.
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.subtracting(.shift).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        var modifiers: UInt32 = 0
        var title = ""
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
            title += "\u{2303}"
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
            title += "\u{2325}"
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
            title += "\u{21E7}"
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
            title += "\u{2318}"
        }
        self.modifiers = modifiers
        self.title = title + Self.name(of: event)
    }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                       kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    private static func name(of event: NSEvent) -> String {
        if let index = functionKeys.firstIndex(of: Int(event.keyCode)) {
            return "F\(index + 1)"
        }
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Delete: return "\u{232B}"
        case kVK_ForwardDelete: return "\u{2326}"
        case kVK_LeftArrow: return "\u{2190}"
        case kVK_RightArrow: return "\u{2192}"
        case kVK_UpArrow: return "\u{2191}"
        case kVK_DownArrow: return "\u{2193}"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

final class GlobalShortcut {
    static let shared = GlobalShortcut()

    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let savedKey = "globalShortcut"

    var saved: Shortcut? {
        get {
            UserDefaults.standard.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.savedKey)
            registerSaved()
        }
    }

    func registerSaved() {
        register(saved)
    }

    /// While a new shortcut is being typed in Settings, the old one mustn't open the panel.
    func pause() {
        register(nil)
    }

    private func register(_ shortcut: Shortcut?) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let shortcut else { return }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4249_5445), id: 1)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in GlobalShortcut.shared.onPress() }
            return noErr
        }, 1, &pressed, nil, &handler)
    }
}
