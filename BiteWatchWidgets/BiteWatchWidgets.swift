import SwiftUI
import WidgetKit
import BiteKit

/// Bite on the watch face and in the Smart Stack: a page, the one it's set to, and the to-dos from
/// every page. A watch's widgets hold no buttons, so these show, and open Bite at a tap, where a
/// to-do is ticked off.
@main
struct BiteWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchPageWidget()
        WatchToDosWidget()
    }
}

/// Bite's ring, as its icon has it, in a page's colour, or in the watch face's where the face
/// tints its widgets: its band the icon's share of the ring across, deeper at the top and lighter
/// at the bottom, as the icon's is lit, with the fine shadow along its top edge that Bite's dots
/// have. In the dark colour alone, flat, it was pale (user, 2026-10-09). Anything in it, such as
/// a count, is set to the ring's size.
struct WatchRing<Inside: View>: View {
    let ink: DotColor
    /// Its share of the room, across: at the phone's Lock Screen share, 0.64, it looked small on
    /// a watch face (user, 2026-10-09).
    var share: CGFloat = 0.84
    @ViewBuilder var inside: (_ diameter: CGFloat) -> Inside

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * share
            ZStack {
                Circle()
                    .strokeBorder(shading(diameter: diameter), lineWidth: diameter * 160 / 770)
                    .widgetAccentable()
                inside(diameter)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func shading(diameter: CGFloat) -> some ShapeStyle {
        let scale = diameter / 18
        return LinearGradient(colors: [Color(platform: PlatformColor(hex: ColorMath.adjustingLightness(ink.light, by: -0.06))),
                                       Color(platform: PlatformColor(hex: ColorMath.adjustingLightness(ink.dark, by: 0.06)))],
                              startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .black.opacity(0.35), radius: 0.7 * scale, x: 0, y: 0.7 * scale))
    }
}

extension WatchRing where Inside == EmptyView {
    init(ink: DotColor, share: CGFloat = 0.84) {
        self.init(ink: ink, share: share) { _ in EmptyView() }
    }
}
