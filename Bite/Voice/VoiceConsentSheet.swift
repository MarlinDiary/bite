import SwiftUI

/// Record, tapped before what's said may go to Soniox and Claude: on `page`, which records once
/// that's allowed (see `VoiceConsentSheet`).
struct RecordingAsked: Identifiable {
    let page: Int
    var id: Int { page }
}

/// Asked the first time Record is tapped, and as Voice Input is turned on in Settings: what's said
/// while recording, and part of the page, go to Soniox to be written down, and, while tidying is
/// on, then to Anthropic's Claude to be tidied (see `VoiceInput.tidies`). App Review wants that
/// said plainly, and allowed, before anything goes to another company's AI (guideline 5.1.2(i),
/// November 2025). Laid out as Bite's welcome is (see `WelcomeSheet`), in the page's colour, as
/// what comes up from its "…" button is: a title, a line for each, two lines each, then Allow,
/// with Not Now under it. Pulled down, it's Not Now.
struct VoiceConsentSheet: View {
    /// After it's allowed, as the sheet goes.
    var onAllow: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text("Voice Input")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 44)
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        row(symbol: "waveform", title: "Written as You Speak",
                            text: "Your voice and part of the page go to Soniox to write down what you say.")
                        if VoiceInput.tidies {
                            row(symbol: "wand.and.sparkles", title: "Tidied When You Stop",
                                text: "Then what you said and part of the page go to Anthropic's Claude.")
                        }
                        row(symbol: "hand.raised", title: "Only When You Record",
                            text: "Nothing is sent at other times, and you can turn this off in Settings.")
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, Self.top)
                .padding(.bottom, 24)
                .frame(maxWidth: Self.width)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 8) {
                Button {
                    Preferences.allowsVoiceInput = true
                    onAllow()
                    dismiss()
                } label: {
                    Text("Allow")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                Button {
                    dismiss()
                } label: {
                    Text("Not Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
            .padding(.horizontal, Self.margin)
            .padding(.bottom, Self.margin * 0.56)
            .frame(maxWidth: Self.width)
        }
    }

    // The welcome's.
    private static let margin: CGFloat = 36
    private static let top: CGFloat = 72
    private static let width: CGFloat = 480
    private static let rowSpacing: CGFloat = 30
    private static let symbolSize: CGFloat = 30

    private func row(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Self.symbolSize * 0.6) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: Self.symbolSize * 1.34, height: Self.symbolSize * 1.2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
