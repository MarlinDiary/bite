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
/// tints its widgets: its band the icon's share of the ring across. Anything in it, such as a
/// count, is set to the ring's size.
struct WatchRing<Inside: View>: View {
    let ink: DotColor
    /// Its share of the room, across.
    var share: CGFloat = 0.64
    @ViewBuilder var inside: (_ diameter: CGFloat) -> Inside

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * share
            ZStack {
                Circle()
                    .strokeBorder(ink.color, lineWidth: diameter * 160 / 770)
                    .widgetAccentable()
                inside(diameter)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension WatchRing where Inside == EmptyView {
    init(ink: DotColor, share: CGFloat = 0.64) {
        self.init(ink: ink, share: share) { _ in EmptyView() }
    }
}
