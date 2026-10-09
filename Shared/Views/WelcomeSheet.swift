import SwiftUI
import BiteKit

/// When Bite's welcome shows: the first time Bite opens on a device, once, and not where tests
/// run or a picture is being taken. `-showWelcome` shows it, for a picture of it.
@MainActor
enum Welcome {
    private static var hasShown = false

    /// Whether to show the welcome now, Bite opening for the first time or not: once only, for a
    /// second window opened meanwhile has it already.
    static func isDue(firstLaunch: Bool) -> Bool {
        guard !hasShown else { return false }
        #if DEBUG
        let isAsked = CommandLine.arguments.contains("-showWelcome")
        #else
        let isAsked = false
        #endif
        guard isAsked || (firstLaunch && showsHere) else { return false }
        hasShown = true
        return true
    }

    private static var showsHere: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil && !CommandLine.arguments.contains("-snapshot")
    }
}

/// Bite's welcome the first time it opens, laid out as Apple's own apps have theirs: the icon's
/// ring, a title, three lines on what Bite is, two lines each, and Continue. The pages say the
/// rest (see `FirstLaunchPages`). On a phone, an iPad and Apple Vision Pro a sheet over the page;
/// on a Mac a window of its own (see `WelcomeWindowController`), which `onContinue` closes.
struct WelcomeSheet: View {
    var onContinue: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            scrolling {
                VStack(spacing: 0) {
                    WelcomeRing()
                        .frame(width: Self.ring, height: Self.ring)
                        .padding(.bottom, Self.ring * 0.32)
                    Text("Welcome to Bite")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.bottom, Self.ring * 0.58)
                    // Each in Bite's orange, the icon's, as an Apple app's are in its own colour.
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        row(symbol: "rectangle.stack", title: "Seven Pages", text: Self.switching)
                        row(symbol: "textformat", title: "Markdown as You Type",
                            text: "Type # for a heading or [] for a to-do, and it turns into the real thing.")
                        row(symbol: "icloud", title: "On All Your Devices",
                            text: "Your pages stay in sync through iCloud, wherever you use Bite.")
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, Self.top)
                .padding(.bottom, 24)
                .frame(maxWidth: Self.width)
                .frame(maxWidth: .infinity)
            }
            Button {
                if let onContinue { onContinue() } else { dismiss() }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            #if os(visionOS)
            .buttonStyle(.borderedProminent)
            #else
            .buttonStyle(.glassProminent)
            #endif
            .controlSize(.large)
            .tint(DotPalette.colors[1].color)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, Self.margin)
            .padding(.bottom, Self.margin * 0.56)
            .frame(maxWidth: Self.width)
        }
        #if os(macOS)
        // The window's width, which its text fills: asked for its own size, the text took the
        // narrowest and the window came out three thousand points tall.
        .frame(width: Self.width)
        #endif
        .interactiveDismissDisabled()
    }

    /// Scrolling where the screen may be too short for it, as a phone on its side or larger text
    /// makes it. A Mac's window is as tall as it is: a scroll view inside gave the window no height
    /// for it, and Continue covered its last line.
    @ViewBuilder
    private func scrolling(@ViewBuilder _ content: () -> some View) -> some View {
        #if os(macOS)
        content()
        #else
        ScrollView {
            content()
        }
        .scrollBounceBehavior(.basedOnSize)
        #endif
    }

    /// How a dot is picked on this device. The other lines read the same everywhere.
    private static var switching: LocalizedStringKey {
        #if os(macOS)
        "One for each dot, for whatever's on your mind. Click a dot, or press ⌘1 to ⌘7, to switch."
        #elseif os(visionOS)
        "One for each dot, for whatever's on your mind. Tap a dot beside the window to switch."
        #else
        "One for each dot, for whatever's on your mind. Swipe or tap to switch."
        #endif
    }

    // A Mac's window is smaller, as its text is, than a phone's sheet.
    #if os(macOS)
    private static let ring: CGFloat = 60
    private static let margin: CGFloat = 40
    private static let top: CGFloat = 40
    private static let width: CGFloat = 420
    private static let rowSpacing: CGFloat = 22
    private static let symbolSize: CGFloat = 24
    #else
    private static let ring: CGFloat = 76
    private static let margin: CGFloat = 36
    private static let top: CGFloat = 72
    private static let width: CGFloat = 480
    private static let rowSpacing: CGFloat = 30
    private static let symbolSize: CGFloat = 30
    #endif

    private func row(symbol: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Self.symbolSize * 0.6) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize, weight: .regular))
                .foregroundStyle(DotPalette.colors[1].color)
                .frame(width: Self.symbolSize * 1.34, height: Self.symbolSize * 1.2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    #if os(macOS)
                    .font(.body)
                    #else
                    .font(.subheadline)
                    #endif
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Bite's ring, as its icon has it: orange, its band the icon's share of the ring across, deeper at
/// the top and lighter at the bottom, with the fine shadow along its top edge that Bite's dots
/// have.
private struct WelcomeRing: View {
    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let ink = DotPalette.colors[1]
            Circle()
                .strokeBorder(LinearGradient(colors: [ink.shade(-0.06), ink.shade(0.06)], startPoint: .top, endPoint: .bottom)
                                .shadow(.inner(color: .black.opacity(0.3), radius: diameter / 40, x: 0, y: diameter / 40)),
                              lineWidth: diameter * 160 / 770)
        }
        // Drawn whole, then put in place: with its shadow drawn in place, a Mac cut off the ring's
        // rightmost column of pixels (user, 2026-10-09).
        .drawingGroup()
    }
}
