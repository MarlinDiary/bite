import Testing
@testable import Bite

/// What the voice relay sends back to go in place of what was said: a tidy Claude finished, never
/// the start of one cut short.
struct VoiceRelayTests {
    @Test func aFinishedTidyIsTheTextBeforeTheMark() throws {
        #expect(try VoiceRelay.whole("- [ ] eggs\n- [ ] bread\u{4}") == "- [ ] eggs\n- [ ] bread")
    }

    /// Cut short, after a long recording or on the way, it would lose the rest of what was said.
    @Test func oneCutShortIsNone() {
        #expect(throws: VoiceRelay.CutShort.self) { try VoiceRelay.whole("Tidied, then cu") }
        #expect(throws: VoiceRelay.CutShort.self) { try VoiceRelay.whole("") }
    }
}
