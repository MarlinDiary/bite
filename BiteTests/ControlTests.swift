import AppIntents
import Testing
import UIKit
@testable import Bite

/// Bite's control, for Control Center, the Lock Screen and the Action button: it comes inside Bite,
/// shows Bite's ring, and opens Bite.
@MainActor
struct ControlTests {
    private var controls: Bundle? {
        Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appending(path: "BiteControls.appex")) }
    }

    @Test func itComesInsideBite() throws {
        let controls = try #require(controls)
        let point = (controls.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"]
        #expect(point as? String == "com.apple.widgetkit-extension")
        // The same build as Bite's, as App Store Connect expects of what comes inside an app.
        #expect(controls.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    /// A control shows a symbol and nothing else: the ring is one, drawn as the system's are.
    @Test func itsRingIsASymbol() throws {
        let ring = try #require(UIImage(named: "bite.ring", in: controls, with: nil))
        #expect(ring.isSymbolImage)
    }

    /// It opens Bite, and stays out of Shortcuts' actions, which have Open App and Open Page.
    @Test func itOpensBite() {
        #expect(OpenBiteIntent.supportedModes == .foreground)
        #expect(!OpenBiteIntent.isDiscoverable)
    }
}
