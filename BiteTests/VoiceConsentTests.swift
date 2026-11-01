import Testing
@testable import Bite

/// Nothing said goes to Soniox or Claude till it's allowed (see `VoiceConsentSheet`).
@MainActor
struct VoiceConsentTests {
    /// Record, tapped before that, asks first: nothing's recorded, and the page it was tapped on
    /// waits for the answer.
    @Test func recordAsksFirst() {
        EditorHarness.privatePreferences
        Preferences.allowsVoiceInput = false
        let window = PageWindow(page: 2)
        VoiceInput.shared.toggle(page: 2, in: window)
        #expect(window.recordingAsked?.page == 2)
        #expect(VoiceInput.shared.phase == .idle)
    }
}
