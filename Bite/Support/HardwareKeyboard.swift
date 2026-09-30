import Foundation
import GameController

/// Whether a hardware keyboard is attached. With one, editing starts without any keys coming up.
enum HardwareKeyboard {
    static var isConnected: Bool {
        GCKeyboard.coalesced != nil
    }
}
