#if DEBUG
import SwiftUI
import BiteKit

/// Real Liquid Glass, at the sizes Bite's widgets use, on each page's wash, for pictures of it the
/// widgets can show: a widget can't hold glass itself. Opened with `-glassSwatches`, a row a page,
/// everything at whole points from the screen's top left (see `GlassSwatches.capsule` and
/// `GlassSwatches.circle`).
struct GlassSwatches: View {
    /// The large widget's dot bar: the app's, at 0.7 of its size.
    static let capsule = CGSize(width: 158, height: 31)
    /// The small widget's arrow: the app's "…" button, at the same 0.7.
    static let circle = CGSize(width: 31, height: 31)
    static let rowHeight: CGFloat = 110
    static let top: CGFloat = 70
    static let capsuleX: CGFloat = 40
    static let circleX: CGFloat = 280
    /// From a row's top to its shapes'.
    static let inset: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .systemBackground)
            ForEach(0..<DotPalette.count, id: \.self) { page in
                let ink = DotPalette.colors[page].color
                ZStack(alignment: .topLeading) {
                    // The page's wash, as behind every page in Bite and its widgets.
                    ink.opacity(PageTint.opacity(dark: colorScheme == .dark))
                        .background(Color(uiColor: .systemBackground))
                    Color.clear
                        .frame(width: Self.capsule.width, height: Self.capsule.height)
                        .glassEffect(.regular, in: .capsule)
                        .offset(x: Self.capsuleX, y: Self.inset)
                    Color.clear
                        .frame(width: Self.circle.width, height: Self.circle.height)
                        .glassEffect(.regular, in: .circle)
                        .offset(x: Self.circleX, y: Self.inset)
                }
                .frame(width: 402, height: Self.rowHeight, alignment: .topLeading)
                .offset(y: Self.top + CGFloat(page) * Self.rowHeight)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }
}
#endif
