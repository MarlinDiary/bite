import SwiftUI
import UIKit
import BiteKit

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

/// Reads which side of a window the system puts its bars down, as on iPhone Duo (see `SideColumn`):
/// none where it puts them across the top and the foot.
struct BarEdgeReader: UIViewRepresentable {
    let onChange: (HorizontalEdge?) -> Void

    func makeUIView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: UIView {
        var onChange: ((HorizontalEdge?) -> Void)?
        private var reported: HorizontalEdge??

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            #if os(iOS)
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ReaderView, _) in
                    view.report()
                }
            }
            #endif
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        func report() {
            guard window != nil else { return }
            let edge = SideColumn.barEdge(traitCollection)
            guard reported != .some(edge) else { return }
            reported = edge
            // Out of this layout pass, which SwiftUI's own is part of.
            DispatchQueue.main.async { [weak self] in self?.onChange?(edge) }
        }
    }
}

/// The column down one side of a screen whose status bar stands there rather than across its top,
/// as iPhone Duo's does. The system turns a page's bars into it: a navigation bar's buttons go to
/// its top and a toolbar's and a tab bar's to its foot, in glass 48 points across where a phone's
/// bars have 44, centred under the camera (measured on iPhone Duo with iOS 27.1, as in Apple's own
/// pictures of it). The column is on the camera's side, the way up the screen is held: upright,
/// the camera and the status bar under it take the column's top; on its side the status bar goes,
/// and the camera's room is at the column's top one way, at its foot the other. Buttons start right
/// against that room, or 24 points from the screen's edge where it isn't. Upside down isn't
/// allowed: the system turns no phone without a home button that way.
///
/// Bite's dots go down the column, as a tab bar's tabs do, midway between the camera's end and the
/// "…" button at the other, whichever way up (user, 2026-10-20). With the keys up over the button
/// they draw in to the page's own dot, in a round button of glass as a tab bar does when it
/// shrinks, and Aa and the "…" button come up out of the keys under it, the three where a
/// navigation bar's buttons go (user, 2026-10-19 and 20). On its side the keys leave the column too
/// little room for three: the page's dot, the first thing to go, draws in where Aa goes, and Aa
/// coming up out of the keys covers it (user, 2026-10-20). The top of the page is the page's.
struct SideColumn: Equatable {
    var edge: HorizontalEdge
    var isTrailing: Bool { edge == .trailing }
    /// The column on the screen, from the screen's edge in to where the page's safe area starts.
    var frame: CGRect
    /// The room the system keeps in the column for the camera, and upright for the status bar
    /// under it, and the camera, on the screen. iPhone Duo's inner display has no camera in the
    /// column: there `camera` is where the outer one's stands, as the status bar's glyphs stand
    /// under its place.
    var cameraRoom: CGRect
    var camera: CGRect
    /// Whether the screen's on its side, wider than tall.
    var isOnItsSide: Bool
    /// Where the screen's folded part way, across the column, with the room to keep clear either
    /// side of the fold: the dots stand off it (see `dots`).
    var fold: CGRect?
    /// Whether it's a phone's screen as big as an iPad's: iPhone Duo's inner one.
    var isOnBigScreen = false
    /// Whether it's a column of Bite's own down a window the status bar isn't in (see
    /// `init(beside:)`).
    var isBeside = false

    /// How thick the column's glass is.
    static let glass: CGFloat = 48
    /// Where the page starts, with nothing over its top: 24 points down, where the system's bars
    /// start on a screen without the status bar across its top.
    static let pageTop: CGFloat = 24

    /// Nil but where the status bar stands at a side: no room kept at the screen's top, and room
    /// kept down one side only. A phone on its side keeps room down both. `occlusions` are what the
    /// system covers, on the screen: its status bar and camera. On a phone's screen as big as an
    /// iPad's, `bigScreen`, iPhone Duo's inner one, a column also stands down the screen's right
    /// with the status bar across the top, as it stands down the right turned the other way: there
    /// the dots go down a side as on the outer screen (user, 2026-10-21). `folds` are where the
    /// screen's folded part way, now. `barEdge` is the side the system puts its bars down, which
    /// a window the status bar isn't in has a column on too (see `init(beside:)`). `screenFolds`:
    /// it's a screen that folds, flat or not, iPhone Duo's inner display, whole or beside another
    /// app.
    init?(safeTop: CGFloat, safeLeading: CGFloat, safeTrailing: CGFloat, size: CGSize, occlusions: [CGRect],
          bigScreen: Bool = false, folds: [CGRect] = [], barEdge: HorizontalEdge? = nil, screenFolds: Bool = false) {
        guard Self.statusBarIsAtSide(safeTop: safeTop, safeLeading: safeLeading, safeTrailing: safeTrailing) else {
            guard safeLeading == 0, safeTrailing == 0 else { return nil }
            if bigScreen, safeTop > 0 {
                self = Self(across: safeTop, size: size, occlusions: occlusions, folds: folds)
            } else if let barEdge {
                self = Self(beside: barEdge, safeTop: safeTop, size: size, folds: folds)
            } else {
                return nil
            }
            return
        }
        edge = safeTrailing > 0 ? .trailing : .leading
        let width = max(safeLeading, safeTrailing)
        let column = CGRect(x: edge == .trailing ? size.width - width : 0, y: 0, width: width, height: size.height)
        frame = column
        isOnItsSide = size.width > size.height
        fold = folds.first { $0.intersects(column) }
        isOnBigScreen = bigScreen
        // The inner display's status bar keeps 124 points, its glyphs, under no camera, centred
        // where the outer one's camera is (measured on iPhone Duo, 2026-10-31).
        let inner = bigScreen || screenFolds
        let atFoot = isOnItsSide && !inner && edge == .trailing
        let inset: CGFloat = 29.33
        let cameraPlace = CGRect(x: edge == .trailing ? size.width - inset - 37 : inset, y: atFoot ? size.height - inset - 37 : inset,
                                 width: 37, height: 37)
        let covered = occlusions.filter { $0.intersects(column) }
        if let room = covered.max(by: { $0.width * $0.height < $1.width * $1.height }),
           let camera = covered.min(by: { $0.width * $0.height < $1.width * $1.height }) {
            cameraRoom = room
            // The room alone is the status bar's, with no camera in it.
            self.camera = covered.count > 1 ? camera : cameraPlace
        } else {
            // Until the system tells what it covers, a moment after the page first shows, as it
            // covers iPhone Duo's outer screen: upright, the room 174 points down the column's top;
            // on its side 82, at the top or, the column on the right, at the foot; the camera 37
            // points across, 29.33 in from the screen's edges. Without, the dots came a moment after
            // the page there. SwiftUI never tells of what's outside the safe area, which the column
            // is.
            let roomHeight: CGFloat = inner ? 124 : isOnItsSide ? 82 : 174
            cameraRoom = CGRect(x: column.minX, y: atFoot ? size.height - roomHeight : 0, width: width, height: roomHeight)
            camera = cameraPlace
        }
    }

    /// The column down a big screen's right, the status bar across its top `safeTop` tall: as wide
    /// as the status bar's own down the right the other way round, its buttons starting under the
    /// status bar, a title centred on the status bar's middle. Its glyphs stand in the top's right
    /// corner, which the page's lines keep clear of (see `textEnd`); till the system tells, as on
    /// iPhone Duo, 144 points across.
    private init(across safeTop: CGFloat, size: CGSize, occlusions: [CGRect], folds: [CGRect]) {
        edge = .trailing
        let width = Self.bigScreenColumn
        let column = CGRect(x: size.width - width, y: 0, width: width, height: size.height)
        frame = column
        isOnItsSide = size.width > size.height
        fold = folds.first { $0.intersects(column) }
        isOnBigScreen = true
        let corner = occlusions.first { $0.minY <= 0 && $0.maxX >= size.width - 1 }
        cameraRoom = corner ?? CGRect(x: size.width - 144, y: 0, width: 144, height: safeTop)
        camera = CGRect(x: column.minX, y: 0, width: width, height: safeTop)
    }

    /// A column of Bite's own down the side of a window the status bar isn't in, the side the system
    /// puts its bars down there, in reach of a thumb: on iPhone Duo's inner screen in Split View,
    /// the side away from the other app (user, 2026-10-31: "放在侧边…方便用户能摸得到"). As wide as
    /// the status bar's column, nothing at its top: its buttons start 24 points down, where the
    /// system's bars start under no status bar, and a title centres on the first.
    private init(beside edge: HorizontalEdge, safeTop: CGFloat, size: CGSize, folds: [CGRect]) {
        self.edge = edge
        let width = Self.bigScreenColumn
        let column = CGRect(x: edge == .trailing ? size.width - width : 0, y: 0, width: width, height: size.height)
        frame = column
        isOnItsSide = size.width > size.height
        fold = folds.first { $0.intersects(column) }
        isBeside = true
        let top = max(safeTop, Self.pageTop)
        cameraRoom = CGRect(x: column.minX, y: 0, width: width, height: top)
        camera = CGRect(x: column.minX, y: top, width: width, height: Self.glass)
    }

    /// How wide the column is on a big screen: as the status bar's own down iPhone Duo's inner
    /// screen.
    static let bigScreenColumn: CGFloat = 84

    /// The side `traits` have the system put its bars down: iPhone Duo's screens, but for its inner
    /// one with the status bar across the top. None elsewhere.
    static func barEdge(_ traits: UITraitCollection) -> HorizontalEdge? {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return nil }
        switch traits.verticalBarEdge {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// Whether `traits` are a phone's screen as big as an iPad's: iPhone Duo's inner one, either way
    /// round.
    static func isBigScreen(_ traits: UITraitCollection) -> Bool {
        traits.userInterfaceIdiom == .phone && traits.horizontalSizeClass == .regular && traits.verticalSizeClass == .regular
    }

    /// Whether `window` has the column: the status bar down a side, or across the top of a big
    /// screen, or the system's bars down a side of a window the status bar isn't in (see `init`).
    static func isShown(in window: UIWindow) -> Bool {
        let insets = window.safeAreaInsets
        guard !statusBarIsAtSide(of: window) else { return true }
        guard insets.left == 0, insets.right == 0 else { return false }
        return isBigScreen(window.traitCollection) && insets.top > 0 || barEdge(window.traitCollection) != nil
    }

    /// Whether the safe area says the status bar stands at a side: none kept at the top, some down
    /// one side only. The system tells where it covers the screen a moment after: Bite launching,
    /// its first frames had no column, and drew the dot bar across the top instead.
    static func statusBarIsAtSide(safeTop: CGFloat, safeLeading: CGFloat, safeTrailing: CGFloat) -> Bool {
        safeTop == 0 && (safeLeading > 0) != (safeTrailing > 0)
    }

    static func statusBarIsAtSide(of window: UIWindow) -> Bool {
        let insets = window.safeAreaInsets
        return statusBarIsAtSide(safeTop: insets.top, safeLeading: insets.left, safeTrailing: insets.right)
    }

    /// `window`'s column, as UIKit tells of it. None on Apple Vision Pro.
    init?(in window: UIWindow) {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return nil }
        let insets = window.safeAreaInsets
        let occlusions = window.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        let divisions = window.reservedRegions(kind: .division, options: .includeInactive)
        self.init(safeTop: insets.top, safeLeading: insets.left, safeTrailing: insets.right, size: window.bounds.size,
                  occlusions: occlusions, bigScreen: Self.isBigScreen(window.traitCollection),
                  folds: divisions.filter(\.isActive).map(\.frame), barEdge: Self.barEdge(window.traitCollection),
                  screenFolds: !divisions.isEmpty)
        #else
        return nil
        #endif
    }

    /// Whether the camera's room is at the column's top, as upright; on its side it's at the foot
    /// one way.
    var roomIsAtTop: Bool { cameraRoom.minY <= frame.minY + 1 }

    /// The column's middle, across: the camera's.
    private var middleX: CGFloat { camera.midX.rounded() }

    /// Where the column's buttons may start at its top, and must end at its foot: right against the
    /// camera's room, or 24 points from the screen's edge.
    var freeTop: CGFloat { roomIsAtTop ? cameraRoom.maxY.rounded() : frame.minY + Self.pageTop }
    var freeBottom: CGFloat { roomIsAtTop ? frame.maxY - 24 : cameraRoom.minY.rounded() }

    /// The edge, towards the dots, of what shows at the camera's end of the column: the foot of the
    /// status bar's glyphs, 23 points over the foot of its room, or of the camera; with the camera at
    /// the column's foot, its top. On iPhone Duo's inner display the glyphs' foot is 16 to 27 over
    /// the room's, as the status bar shows the location arrow or not: 23 sits between.
    var cameraEnd: CGFloat {
        // Beside a window with nothing at the column's top, from where its buttons may start.
        if isBeside { return freeTop }
        return roomIsAtTop ? max(camera.maxY, cameraRoom.maxY - 23) : camera.minY
    }

    /// The "…" button, keys down: at the column's end away from the camera, where the system puts a
    /// toolbar's last button, or with the camera at the foot, at the top (user, 2026-10-20), where it
    /// puts a navigation bar's first.
    var button: CGRect {
        let y = roomIsAtTop ? freeBottom - Self.glass : freeTop
        return CGRect(x: middleX - Self.glass / 2, y: y, width: Self.glass, height: Self.glass)
    }

    /// The dots: midway between the camera's end and the button; or, would that lay them over the
    /// fold while the screen's folded part way, midway between the fold and the button: off it, as
    /// the system asks of controls, with the button on the half that lies on the table when the
    /// phone stands open like a laptop, where the system puts controls, as steadier to tap. Flat,
    /// they kept off the fold too, and stood high (user, 2026-10-31).
    var dots: CGRect {
        var middle = roomIsAtTop ? (cameraEnd + button.minY) / 2 : (button.maxY + cameraEnd) / 2
        if let fold, abs(middle - fold.midY) < (DotSwitcher.width + fold.height) / 2 {
            middle = roomIsAtTop ? (fold.maxY + button.minY) / 2 : (button.maxY + fold.minY) / 2
        }
        return CGRect(x: button.minX, y: (middle - DotSwitcher.width / 2).rounded(), width: Self.glass, height: DotSwitcher.width)
    }

    /// How far across from the column's side the page's lines may run: to the column, or to the
    /// status bar's glyphs in the top's corner where they're further out.
    var textEnd: CGFloat {
        isTrailing ? min(frame.minX, cameraRoom.minX) : max(frame.maxX, cameraRoom.maxX)
    }

    /// Whether the keys leave the column room for two buttons only: iPhone Duo's outer screen on its
    /// side. There the page's dot turns into Aa; its inner one, as wide, is tall enough for all
    /// three.
    var isShort: Bool { isOnItsSide && frame.height < 600 }

    /// The column's top buttons, where a navigation bar's go: the first at the column's top, each
    /// next 12 points under the one before. With the keys up, the page's dot, Aa and the "…" button;
    /// on its side Aa and the button.
    var firstButton: CGRect {
        CGRect(x: button.minX, y: freeTop, width: Self.glass, height: Self.glass)
    }
    var secondButton: CGRect {
        firstButton.offsetBy(dx: 0, dy: Self.glass + 12)
    }
    var thirdButton: CGRect {
        secondButton.offsetBy(dx: 0, dy: Self.glass + 12)
    }

    /// How far down the middle of the column's top is: the camera's, at the top, or else its first
    /// button's. A title on the page's first line is centred on it (see `BiteTextView`).
    var titleMiddle: CGFloat { roomIsAtTop ? camera.midY : firstButton.midY }

    /// Where the page's dot, Aa and the "…" button go with the keys up: the dot at the top and the
    /// two under it; on a short screen the dot where it turns into Aa, at the column's top, the button
    /// under it, or with the camera at the foot staying at the top over it.
    var typingFormat: CGRect { isShort && roomIsAtTop ? firstButton : secondButton }
    var typingMenu: CGRect { !isShort ? thirdButton : roomIsAtTop ? secondButton : firstButton }
    var typingDot: CGRect { isShort ? typingFormat : firstButton }

    /// The page `by` pages on from `page`, round from the last to the first and back: what the
    /// page's dot opens, drawn in.
    static func page(_ page: Int, steppedBy by: Int) -> Int {
        (page + by % DotPalette.count + DotPalette.count) % DotPalette.count
    }

    /// Whether the dots draw in with keys `keys` tall over the foot of a screen `height` tall: on-screen
    /// keys up over where the dots stand, or a hardware keyboard's short strip, or on a big screen
    /// any keys, over the "…" button.
    /// Waiting for on-screen keys to be down past the button, the dots opened out late after keys a
    /// finger dragged away. `onScreen` tells on-screen keys going down from a strip.
    func drawsIn(keys: CGFloat, height: CGFloat, onScreen: Bool) -> Bool {
        guard keys > 0 else { return false }
        let top = height - keys
        // On a big screen the keys come up nowhere near the dots, but over the button, Aa with it.
        return onScreen && !isOnBigScreen ? top < dots.maxY : top < button.maxY
    }
}
