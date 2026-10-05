import UIKit

/// Where the dot bar and the "…" button sit: where the system puts a navigation bar's buttons,
/// measured on the iPhone 17, Air and 17e on iOS 27. Upright, their top is the safe area's, just
/// below the status bar, with the system's least margins at the sides: 16 points, 20 on a phone
/// 414 points wide or more. On its side, with no status bar, they're 24 points down and 38 in from
/// the screen's edges, out by its rounded corners, as Notes' are. Bite's sat 2 points down there,
/// against the top edge, and inside the room kept beside the Dynamic Island, far from the corner.
struct TopBarPlacement: Equatable {
    /// From the top of the screen to the top of the bar.
    var top: CGFloat
    /// From each side of the screen to the ends of the bar.
    var side: CGFloat

    /// How far down from its top the bar covers the page: the bar, and a little air under it.
    static let reach: CGFloat = 50

    init(safeTop: CGFloat, safeSides: CGFloat, width: CGFloat) {
        let margin: CGFloat = width >= 414 ? 20 : 16
        if safeTop > 0 {
            top = safeTop
            side = margin
        } else if safeSides > 0 {
            top = 24
            side = 38
        } else {
            // A phone with square corners, on its side: not measured.
            top = 8
            side = margin
        }
    }
}
