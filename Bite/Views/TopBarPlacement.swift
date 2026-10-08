import SwiftUI
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
        #if SHARE_EXTENSION
        // In the share sheet, where the system puts a sheet's buttons: 16 points in from its top and
        // sides, clear of its rounded corners.
        top = 16
        side = 16
        return
        #endif
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

extension TopBarPlacement {
    /// Whether the button at the bar's start clears the dots in the middle, by a little, where it
    /// stands: in from the side, or past the system's window controls on an iPad's window that
    /// isn't full screen. A window made narrow pressed Aa up against the dots, and it goes then
    /// (user, 2026-10-09). Past the controls, the toolbar Aa is in puts it 4 points further in
    /// than they reach, 66 points on a 13-inch iPad: it shows from 470 points wide.
    static func startButtonFits(width: CGFloat, side: CGFloat, windowControls: CGFloat) -> Bool {
        // Only the controls push it in. Without them the bar was made to hold it, as on a phone
        // and in the share extension.
        guard windowControls > side else { return true }
        let dots = (width - DotSwitcher.width) / 2
        return windowControls + DotSwitcher.height + 12 <= dots
    }
}

/// Reads how far in from a window's start the system's window controls reach, at its top: on an
/// iPad's window that isn't full screen. None full screen, or on a phone.
struct WindowControlsReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var reported: CGFloat?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        func report() {
            let controls = directionalEdgeInsets(for: .safeArea(cornerAdaptation: .horizontal)).leading
            guard controls != reported else { return }
            reported = controls
            // Out of this layout pass, which SwiftUI's own is part of.
            DispatchQueue.main.async { [weak self] in self?.onChange?(controls) }
        }
    }
}
