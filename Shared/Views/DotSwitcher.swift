import SwiftUI
import BiteKit

/// The seven dots in a glass capsule. A dot shows its colour only once it has something in it,
/// and the dot of the page on screen is filled in, and, when Settings says so, glows in its
/// colour. Touch a dot to open its page, or slide along the bar: whichever dot is under the
/// finger, the page goes there.
struct DotSwitcher: View {
    @Binding var selection: Int
    /// The page on screen. While a swipe moves between pages, the fill follows it.
    let highlighted: Int
    /// Called just before a tap opens another dot's page, as opposed to sliding onto it.
    var onTap: () -> Void = {}
    /// Called with true as a finger comes down on the bar, before it opens a page, and with
    /// false once it's lifted.
    var onTouch: (Bool) -> Void = { _ in }
    @Environment(DotStore.self) private var store
    @Environment(\.dotColors) private var dotColors
    /// The dot under the finger while one is down on the bar.
    @State private var touchedDot: Int?
    /// Whether a finger is down on the bar. Unlike `onEnded`, this also ends when the system
    /// takes the touch away.
    @GestureState private var isTouched = false
    /// Whether the page on screen's dot glows, as chosen in Settings.
    @State private var dotGlows = Preferences.dotGlows

    /// Every size here is a phone's, times this. A Mac's controls are smaller than a phone's,
    /// which are made for a finger: there the bar is 30 points tall, as a toolbar's controls are.
    #if os(macOS)
    static let scale: CGFloat = 30.0 / 44.0
    #else
    static let scale: CGFloat = 1
    #endif
    static let height = 44 * scale
    /// The capsule's width: the dots, and the space at either end.
    static let width = (CGFloat(DotPalette.count) * 30 + 2 * 8) * scale

    private let dotWidth = 30 * scale
    private let inset = 8 * scale
    private var scale: CGFloat { Self.scale }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<DotPalette.count, id: \.self) { dot in
                let isSelected = highlighted == dot
                let hasContent = dotColors.isColoured(dot, isSelected: isSelected, isEmpty: store.isEmpty)
                // An empty page's grey isn't lit: lit past white, a grey is white.
                DotIndicator(ink: hasContent ? DotPalette.colors[dot] : DotPalette.empty, isSelected: isSelected,
                             glows: dotGlows && hasContent)
                    .frame(width: dotWidth, height: Self.height)
                    // The dot under the finger dims a little, as one piece, instantly.
                    .compositingGroup()
                    .opacity(touchedDot == dot ? 0.72 : 1)
                    .accessibilityElement()
                    .accessibilityLabel("\(DotPalette.colors[dot].name) dot")
                    .accessibilityValue(hasContent ? "Has content" : "Empty")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction {
                        guard selection != dot else { return }
                        onTap()
                        selection = dot
                    }
            }
        }
        .padding(.horizontal, inset)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isTouched) { _, state, _ in state = true }
                .onChanged { value in
                    let dot = dot(at: value.location.x)
                    // The finger's first touch is a tap; every dot after that, a slide.
                    let isTouchDown = touchedDot == nil
                    if isTouchDown { onTouch(true) }
                    if touchedDot != dot { touchedDot = dot }
                    guard selection != dot else { return }
                    if isTouchDown { onTap() }
                    selection = dot
                }
                .onEnded { _ in lift() }
        )
        .onChange(of: isTouched) { _, isTouched in
            if !isTouched { lift() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Preferences.didChange)) { _ in
            dotGlows = Preferences.dotGlows
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func lift() {
        guard touchedDot != nil else { return }
        touchedDot = nil
        onTouch(false)
    }

    /// The dot at `x` across the bar; past either end, the one at that end.
    private func dot(at x: CGFloat) -> Int {
        min(max(Int(((x - inset) / dotWidth).rounded(.down)), 0), DotPalette.count - 1)
    }
}

/// Which dots the dot bar shows in their colour: those whose page has something on it, as Bite's
/// does. The share extension's, where each page shows what's shared at its end, shows each page as
/// Add would leave it: the page on screen with what's shared, as it is, and the others with their
/// own lines, `ownIsEmpty`. What's shared taken off a page with nothing else on it, its dot is
/// empty again.
enum DotColors {
    case byContent
    case asAdded(ownIsEmpty: [Bool])

    func isColoured(_ dot: Int, isSelected: Bool, isEmpty: [Bool]) -> Bool {
        switch self {
        case .byContent: !isEmpty[dot]
        case .asAdded(let ownIsEmpty): isSelected ? !isEmpty[dot] : !ownIsEmpty[dot]
        }
    }
}

extension EnvironmentValues {
    @Entry var dotColors: DotColors = .byContent
}

/// A ring that is solid when selected. It looks set into the capsule rather than sitting on top:
/// the colour darkens toward the top edge, where a fine inner shadow falls. Changes are instant,
/// with no animation, like Tot. One that glows, the page on screen's in the dot bar when Settings
/// says so, is lit past white on a screen that can, HDR, as nothing else is: every colour as
/// brightly.
struct DotIndicator: View {
    let ink: DotColor
    let isSelected: Bool
    var glows = false
    @Environment(\.colorScheme) private var colorScheme

    /// How bright a glowing dot is at its brightest, its bottom edge, against white's 1.
    static let glow: Double = 1.8
    /// How much darker the colour is at the top edge, and lighter at the bottom.
    private static let topShade = -0.10, bottomShade = 0.07

    var body: some View {
        let isLit = glows && isSelected
        let light = isLit ? lighting : (top: 0, bottom: 0, shadow: 1)
        let shading = LinearGradient(colors: [ink.shade(Self.topShade).exposureAdjust(light.top),
                                              ink.shade(Self.bottomShade).exposureAdjust(light.bottom)],
                                     startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .black.opacity((colorScheme == .dark ? 0.35 : 0.22) * light.shadow), radius: 0.7, x: 0, y: 0.7))
        // One shape per state: a ring drawn under a fill made the two layers dim separately when
        // pressed, so the rim looked darker than the middle.
        Group {
            if isSelected {
                Circle().fill(shading)
            } else {
                Circle().strokeBorder(shading, lineWidth: 3 * DotSwitcher.scale)
            }
        }
        .frame(width: 18 * DotSwitcher.scale, height: 18 * DotSwitcher.scale)
        .allowedDynamicRange(isLit ? .high : nil)
        .transaction { $0.animation = nil }
    }

    /// A glowing dot has its own light added evenly over it, as a lamp set into the bar would
    /// shine, as much as brings its bottom edge to `glow`, whatever the colour: so the shade at the
    /// top is lit too, only a little less. In stops, how much brighter that makes each end of the
    /// shading; and how much fainter the rim's shadow, which falls on the colour but not the light.
    private var lighting: (top: Double, bottom: Double, shadow: Double) {
        let hex = colorScheme == .dark ? ink.dark : ink.light
        let top = ColorMath.brightestChannel(of: ColorMath.adjustingLightness(hex, by: Self.topShade))
        let bottom = ColorMath.brightestChannel(of: ColorMath.adjustingLightness(hex, by: Self.bottomShade))
        let light = Self.glow - bottom
        return (log2((top + light) / top), log2(Self.glow / bottom), top / (top + light))
    }
}
