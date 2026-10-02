import SwiftUI
import BiteKit

/// The seven dots in a glass capsule. A dot shows its colour only once it has something in it,
/// and the dot of the page on screen is filled in. Touch a dot to open its page, or slide along
/// the bar: whichever dot is under the finger, the page goes there.
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
    /// The dot under the finger while one is down on the bar.
    @State private var touchedDot: Int?
    /// Whether a finger is down on the bar. Unlike `onEnded`, this also ends when the system
    /// takes the touch away.
    @GestureState private var isTouched = false

    /// Every size here is a phone's, times this. A Mac's controls are smaller than a phone's,
    /// which are made for a finger: there the bar is 30 points tall, as a toolbar's controls are.
    #if os(macOS)
    static let scale: CGFloat = 30.0 / 44.0
    #else
    static let scale: CGFloat = 1
    #endif
    static let height = 44 * scale

    private let dotWidth = 30 * scale
    private let inset = 8 * scale
    private var scale: CGFloat { Self.scale }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<DotPalette.count, id: \.self) { dot in
                let isSelected = highlighted == dot
                let hasContent = !store.isEmpty[dot]
                DotIndicator(ink: hasContent ? DotPalette.colors[dot] : DotPalette.empty, isSelected: isSelected)
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

/// A ring that is solid when selected. It looks set into the capsule rather than sitting on top:
/// the colour darkens toward the top edge, where a fine inner shadow falls. Changes are instant,
/// with no animation, like Tot.
struct DotIndicator: View {
    let ink: DotColor
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shading = LinearGradient(colors: [ink.shade(-0.10), ink.shade(0.07)], startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.22), radius: 0.7, x: 0, y: 0.7))
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
        .transaction { $0.animation = nil }
    }
}
