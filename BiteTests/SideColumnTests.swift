import Testing
import SwiftUI
import UIKit
@testable import Bite

/// iPhone Duo folded: the status bar down the screen's right side, and the dots down it too, midway
/// between the status bar and the "…" button at its foot, or the keys once they're up over it.
@MainActor
struct SideColumnTests {
    /// The outer screen as iOS 27.1 lays it out: room kept down its right side, where the system
    /// covers the camera and the status bar above it.
    private static let folded = CGSize(width: 466, height: 678)
    private static let covered = [CGRect(x: 399.67, y: 29.33, width: 37, height: 37), CGRect(x: 382, y: 0, width: 84, height: 174)]
    /// The same with a Live Activity in the Dynamic Island, the status bar's room grown down the
    /// column (measured on iPhone Duo with iOS 27.2, music playing).
    private static let coveredByLiveActivity = [CGRect(x: 399.67, y: 29.33, width: 37, height: 37),
                                                CGRect(x: 382, y: 0, width: 84, height: 264.33)]

    private func column() -> SideColumn? {
        SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: Self.folded, occlusions: Self.covered)
    }

    private func columnUnderLiveActivity() -> SideColumn? {
        SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: Self.folded, occlusions: Self.coveredByLiveActivity)
    }

    /// The "…" button where the system puts a toolbar's last button there, in glass 48 points
    /// across, and the dots midway between the status bar and it. Drawn in, the page's dot and the
    /// button go where a navigation bar's buttons do, under the status bar.
    @Test func theDotsStandMidwayBetweenTheStatusBarAndTheMenu() throws {
        let column = try #require(column())
        #expect(column.edge == .trailing)
        #expect(column.frame == CGRect(x: 382, y: 0, width: 84, height: 678))
        #expect(column.cameraEnd == 151)
        #expect(column.button == CGRect(x: 394, y: 606, width: 48, height: 48))
        #expect(column.dots == CGRect(x: 394, y: 266, width: 48, height: DotSwitcher.width))
        // As much room above them as below, give or take rounding to whole points.
        #expect(abs((column.dots.minY - column.cameraEnd) - (column.button.minY - column.dots.maxY)) <= 1)
        #expect(column.firstButton == CGRect(x: 394, y: 174, width: 48, height: 48))
        #expect(column.secondButton == CGRect(x: 394, y: 234, width: 48, height: 48))
        #expect(column.thirdButton == CGRect(x: 394, y: 294, width: 48, height: 48))
        #expect(column.titleMiddle == 29.33 + 37 / 2)
        #expect(!column.isOnItsSide)
    }

    /// A Live Activity in the Dynamic Island grows the status bar's room down the column: Aa's panel,
    /// which the system keeps between the room and the keys, would stand squashed there, so the
    /// format bar comes up on the keys, as Notes' toolbar does, and the column clears out of their
    /// way (user, 2026-11-01). With no Live Activity, or on its side, Aa stays down the column. The
    /// buttons start clear of the room, to the whole point, for Aa's toolbar moves Aa off its glass
    /// to keep clear of any of it. The dots stand midway between the grown status bar and the button.
    @Test func underAStatusBarGrownForALiveActivityTheFormatBarComesUp() throws {
        let plain = try #require(column())
        #expect(!plain.formatsOnKeys)
        // Aa's panel fits between the status bar and Chinese keys.
        #expect(plain.freeTop + SideColumn.panelHeight <= 678 - 305.5)
        #expect(SideColumn.panelHeight == FormatPanelView.Metrics.compact.size.height)
        let column = try #require(columnUnderLiveActivity())
        #expect(column.formatsOnKeys)
        #expect(!column.isShort)
        #expect(column.firstButton == CGRect(x: 394, y: 265, width: 48, height: 48))
        #expect(!column.firstButton.intersects(column.cameraRoom))
        #expect(column.cameraEnd == 264.33 - 23)
        #expect(column.dots == CGRect(x: 394, y: 311, width: 48, height: DotSwitcher.width))
        #expect(column.drawsIn(keys: 678 - 412, height: 678, onScreen: true))
        let onItsSide = try #require(SideColumn(safeTop: 0, safeLeading: 84, safeTrailing: 0, size: CGSize(width: 678, height: 466),
                                                occlusions: [CGRect(x: 29.33, y: 29.33, width: 37, height: 37), CGRect(x: 0, y: 0, width: 84, height: 82)]))
        #expect(!onItsSide.formatsOnKeys)
        let inner = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: CGSize(width: 951, height: 669),
                                            occlusions: [CGRect(x: 867, y: 0, width: 84, height: 124)], bigScreen: true))
        #expect(!inner.formatsOnKeys)
    }

    /// On its side the column is on the camera's side: on the left with the camera at its top, its
    /// buttons starting right under the camera's room and the "…" button 24 points up from the
    /// screen's foot; on the right with the camera at its foot, its buttons starting 24 points
    /// down, the button among them, at the column's end away from the camera (measured on iPhone
    /// Duo with iOS 27.1). The dots stand midway between the camera and the button, and draw in to
    /// the page's dot with the keys up where Aa comes to cover it, the button by it.
    @Test func onItsSideTheColumnIsOnTheCamerasSide() throws {
        let wide = CGSize(width: 678, height: 466)
        let left = try #require(SideColumn(safeTop: 0, safeLeading: 84, safeTrailing: 0, size: wide,
                                           occlusions: [CGRect(x: 29.33, y: 29.33, width: 37, height: 37), CGRect(x: 0, y: 0, width: 84, height: 82)]))
        #expect(left.edge == .leading)
        #expect(left.isOnItsSide)
        #expect(left.firstButton == CGRect(x: 24, y: 82, width: 48, height: 48))
        #expect(left.button == CGRect(x: 24, y: 394, width: 48, height: 48))
        #expect(left.dots == CGRect(x: 24, y: 117, width: 48, height: DotSwitcher.width))
        #expect(left.titleMiddle == 29.33 + 37 / 2)
        #expect(left.typingFormat == left.firstButton)
        #expect(left.typingMenu == left.secondButton)
        #expect(left.typingDot == left.typingFormat)
        let right = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: wide,
                                            occlusions: [CGRect(x: 611.67, y: 399.67, width: 37, height: 37), CGRect(x: 594, y: 384, width: 84, height: 82)]))
        #expect(right.edge == .trailing)
        #expect(right.firstButton == CGRect(x: 606, y: 24, width: 48, height: 48))
        #expect(right.button == right.firstButton)
        // Midway between the button's foot, 72, and the camera's top, 399.67.
        #expect(right.dots == CGRect(x: 606, y: 123, width: 48, height: DotSwitcher.width))
        #expect(right.titleMiddle == 48)
        #expect(right.typingMenu == right.button)
        #expect(right.typingFormat == right.secondButton)
        #expect(right.typingDot == right.typingFormat)
        // Before the system tells what it covers, as it covers the outer screen each way.
        for column in [left, right] {
            let guess = try #require(SideColumn(safeTop: 0, safeLeading: column.isTrailing ? 0 : 84, safeTrailing: column.isTrailing ? 84 : 0,
                                                size: wide, occlusions: []))
            #expect(guess.firstButton == column.firstButton)
            #expect(guess.button == column.button)
            #expect(guess.dots == column.dots)
            #expect(abs(guess.titleMiddle - column.titleMiddle) < 0.01)
        }
    }

    /// On iPhone Duo's inner screen, as big as an iPad's: book-open wide, the status bar's own
    /// column down the right, the dots midway down it, the keys leaving room for all three buttons;
    /// upright, the status bar across the top, a column of the dots' own down the right under it,
    /// the page's lines clear of the status bar's glyphs in the corner, a title centred on the
    /// status bar, the dots midway down, and off the fold, across the middle, while the screen's
    /// folded part way (measured with iOS 27.1).
    @Test func onTheInnerScreenTheDotsGoDownTheRightToo() throws {
        let wide = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: CGSize(width: 951, height: 669),
                                           occlusions: [CGRect(x: 867, y: 0, width: 84, height: 124)], bigScreen: true,
                                           folds: [CGRect(x: 455.5, y: 0, width: 40, height: 669)]))
        #expect(wide.frame == CGRect(x: 867, y: 0, width: 84, height: 669))
        #expect(wide.fold == nil)
        #expect(!wide.isShort)
        #expect(wide.textEnd == 867)
        // Under the status bar's glyphs, which stand where the outer display's camera does, and
        // midway between their foot and the button; a title as high as there.
        #expect(wide.button == CGRect(x: 879, y: 597, width: 48, height: 48))
        #expect(wide.cameraEnd == 101)
        #expect(wide.dots.minY == 236)
        #expect(abs(wide.titleMiddle - 47.83) < 0.01)
        // The same before the system tells what it covers, as SwiftUI never does.
        let untold = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: CGSize(width: 951, height: 669),
                                             occlusions: [], bigScreen: true))
        #expect(untold.dots == wide.dots)
        #expect(untold.button == wide.button)
        // Beside another app, its status bar's room is the inner display's still.
        let beside = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: CGSize(width: 469, height: 669),
                                             occlusions: [CGRect(x: 385, y: 0, width: 84, height: 124)], screenFolds: true))
        let besideUntold = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: CGSize(width: 469, height: 669),
                                                   occlusions: [], screenFolds: true))
        #expect(beside.dots == besideUntold.dots)
        #expect(beside.dots.minY == 236)
        #expect(beside.button.minX == 397)
        #expect(wide.typingDot == wide.firstButton)
        #expect(wide.typingFormat == wide.secondButton)
        #expect(wide.typingMenu == wide.thirdButton)
        let flat = try #require(SideColumn(safeTop: 82, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 669, height: 951),
                                           occlusions: [CGRect(x: 525, y: 0, width: 144, height: 82)], bigScreen: true))
        // Midway between the status bar and the button.
        #expect(flat.dots.midY == (82 + 879) / 2 + 0.5)
        let upright = try #require(SideColumn(safeTop: 82, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 669, height: 951),
                                              occlusions: [CGRect(x: 525, y: 0, width: 144, height: 82)], bigScreen: true,
                                              folds: [CGRect(x: 0, y: 455.5, width: 669, height: 40)]))
        #expect(upright.isTrailing)
        #expect(upright.frame == CGRect(x: 585, y: 0, width: 84, height: 951))
        #expect(upright.textEnd == 525)
        #expect(upright.titleMiddle == 41)
        #expect(upright.firstButton == CGRect(x: 603, y: 82, width: 48, height: 48))
        #expect(upright.button == CGRect(x: 603, y: 879, width: 48, height: 48))
        // Folded part way, midway between the fold and the button, on the half that lies on the
        // table, not across the fold.
        #expect(upright.dots.minY == 574)
        #expect(upright.dots.minY > 495.5)
        #expect(upright.dots.maxY < 879)
        // Keys up over the button draw the dots in, though they come nowhere near them.
        #expect(upright.drawsIn(keys: 351, height: 951, onScreen: true))
        #expect(!upright.drawsIn(keys: 0, height: 951, onScreen: true))
        // The same screen size on a phone that isn't as big has no column across the top.
        #expect(SideColumn(safeTop: 82, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 669, height: 951),
                           occlusions: [CGRect(x: 525, y: 0, width: 144, height: 82)]) == nil)
    }

    /// In iPhone Duo's Split View a window the status bar isn't in has the column too, down the side
    /// the system puts its bars: buttons from 24 points down, a title centred on the first, the dots
    /// midway down to the "…" at the foot.
    @Test func aWindowTheStatusBarIsntInHasTheColumnDownTheBarsSide() throws {
        let left = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 455, height: 669),
                                           occlusions: [], barEdge: .leading))
        #expect(left.isBeside)
        #expect(!left.isTrailing)
        #expect(!left.isShort)
        #expect(left.frame == CGRect(x: 0, y: 0, width: 84, height: 669))
        #expect(left.textEnd == 84)
        #expect(left.firstButton == CGRect(x: 18, y: 24, width: 48, height: 48))
        #expect(left.button == CGRect(x: 18, y: 597, width: 48, height: 48))
        #expect(left.titleMiddle == 48)
        #expect(left.dots.midY == 311)
        let right = try #require(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 455, height: 669),
                                            occlusions: [], barEdge: .trailing))
        #expect(right.frame == CGRect(x: 371, y: 0, width: 84, height: 669))
        #expect(right.textEnd == 371)
        // No side for the bars, as on any other phone: no column.
        #expect(SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 455, height: 669), occlusions: []) == nil)
    }

    /// On-screen keys up over where the dots stand draw them in: English keys, and Chinese ones a
    /// row of candidates taller; dragged down past the dots' foot, they open out again. A hardware
    /// keyboard's strip draws them in once it's over the "…" button.
    @Test func keysUpOverTheDotsDrawThemIn() throws {
        let column = try #require(column())
        #expect(!column.drawsIn(keys: 0, height: 678, onScreen: true))
        #expect(column.drawsIn(keys: 678 - 412, height: 678, onScreen: true))
        #expect(column.drawsIn(keys: 678 - 372.5, height: 678, onScreen: true))
        #expect(!column.drawsIn(keys: 678 - 520, height: 678, onScreen: true))
        // On-screen keys nearly gone, and a strip of the same height.
        #expect(!column.drawsIn(keys: 55, height: 678, onScreen: true))
        #expect(column.drawsIn(keys: 55, height: 678, onScreen: false))
        #expect(!column.drawsIn(keys: 20, height: 678, onScreen: false))
    }

    /// The page's dot, drawn in, opens the next page, the last one's next the first; VoiceOver can
    /// go back too, the first one's before the last.
    @Test func thePagesDotGoesRoundThePages() {
        #expect(SideColumn.page(0, steppedBy: 1) == 1)
        #expect(SideColumn.page(6, steppedBy: 1) == 0)
        #expect(SideColumn.page(0, steppedBy: -1) == 6)
        #expect(SideColumn.page(3, steppedBy: -1) == 2)
    }

    /// A phone upright or on its side has no column. The safe area alone tells the status bar is at
    /// a side, before the system says what it covers: till then the column is as on iPhone Duo's
    /// outer screen, so the dots are there from the first frame.
    @Test func onlyAScreenWithItsStatusBarDownASideHasAColumn() {
        #expect(SideColumn.statusBarIsAtSide(safeTop: 0, safeLeading: 0, safeTrailing: 84))
        #expect(!SideColumn.statusBarIsAtSide(safeTop: 62, safeLeading: 0, safeTrailing: 0))
        #expect(!SideColumn.statusBarIsAtSide(safeTop: 0, safeLeading: 62, safeTrailing: 62))
        #expect(!SideColumn.statusBarIsAtSide(safeTop: 0, safeLeading: 0, safeTrailing: 0))
        let island = CGRect(x: 138, y: 11, width: 126, height: 37)
        #expect(SideColumn(safeTop: 62, safeLeading: 0, safeTrailing: 0, size: CGSize(width: 402, height: 874), occlusions: [island]) == nil)
        #expect(SideColumn(safeTop: 0, safeLeading: 62, safeTrailing: 62, size: CGSize(width: 874, height: 402),
                           occlusions: [CGRect(x: 11, y: 138, width: 37, height: 126)]) == nil)
        // Before the system tells what it covers, as it covers the outer screen.
        let guess = SideColumn(safeTop: 0, safeLeading: 0, safeTrailing: 84, size: Self.folded, occlusions: [])
        #expect(guess?.firstButton == column()?.firstButton)
        #expect(guess?.button == column()?.button)
        #expect(guess?.dots == column()?.dots)
        #expect(abs((guess?.titleMiddle ?? 0) - (column()?.titleMiddle ?? 1)) < 0.01)
    }

    /// The dots draw in to the page's dot as the keys come up over the "…" button, in the keys' own
    /// animation, and Aa and the button come up under it out of the keys, each in a spring of its
    /// own, Aa from under the screen's foot; and back as the keys go.
    @Test func theDotsDrawInWithTheKeys() throws {
        let column = try #require(column())
        let pager = DotPagerCoordinator()
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: Self.folded))
        }
        window.frame = CGRect(origin: .zero, size: Self.folded)
        EditorHarness.show(window)
        pager.container.frame = window.bounds
        window.addSubview(pager.container)
        pager.container.layoutIfNeeded()
        let controller = ColumnController(dots: Color.clear, dot: Color.clear, menu: Color.clear)
        controller.loadViewIfNeeded()
        let mover = ColumnMover()
        mover.attachForTesting(controller, column: column, height: 678)
        let left = column.frame.minX
        let underFoot = CGRect(x: column.secondButton.minX - left, y: 678 + 10, width: 48, height: 48)
        #expect(controller.glassFrameForTesting == column.dots.offsetBy(dx: -left, dy: 0))
        #expect(controller.menuFrameForTesting == column.button.offsetBy(dx: -left, dy: 0))
        #expect(controller.formatFrameForTesting == underFoot)
        pager.columnMover = mover
        let container = pager.container
        pager.controllers[2].focus()
        container.keysForTesting = 678 - 372.5
        UIView.animate(withDuration: 0.3) {
            container.setNeedsLayout()
            container.layoutIfNeeded()
        }
        #expect(mover.isDrawnIn)
        #expect(controller.glassFrameForTesting == column.firstButton.offsetBy(dx: -left, dy: 0))
        #expect(controller.formatFrameForTesting == column.secondButton.offsetBy(dx: -left, dy: 0))
        #expect(controller.menuFrameForTesting == column.thirdButton.offsetBy(dx: -left, dy: 0))
        #expect(controller.glassIsMovingForTesting)
        #expect(controller.formatIsMovingForTesting)
        #expect(controller.menuIsMovingForTesting)
        // A Live Activity coming while the keys are up: the format bar comes up on them, and the
        // page's dot, Aa and the button go down under them, out of sight; and back as it goes.
        let grown = try #require(columnUnderLiveActivity())
        mover.attachForTesting(controller, column: grown, height: 678)
        #expect(mover.isDrawnIn)
        #expect(controller.glassFrameForTesting == CGRect(x: grown.firstButton.minX - left, y: 678 + 10, width: 48, height: 48))
        #expect(controller.formatFrameForTesting == CGRect(x: grown.secondButton.minX - left, y: 678 + 10, width: 48, height: 48))
        #expect(controller.menuFrameForTesting == CGRect(x: grown.button.minX - left, y: 678 + 10, width: 48, height: 48))
        mover.attachForTesting(controller, column: column, height: 678)
        #expect(mover.isDrawnIn)
        #expect(controller.glassFrameForTesting == column.firstButton.offsetBy(dx: -left, dy: 0))
        #expect(controller.formatFrameForTesting == column.secondButton.offsetBy(dx: -left, dy: 0))
        #expect(controller.menuFrameForTesting == column.thirdButton.offsetBy(dx: -left, dy: 0))
        pager.controllers[2].textView.resignFirstResponder()
        container.keysForTesting = 0
        container.setNeedsLayout()
        container.layoutIfNeeded()
        #expect(!mover.isDrawnIn)
        #expect(controller.glassFrameForTesting == column.dots.offsetBy(dx: -left, dy: 0))
        #expect(controller.menuFrameForTesting == column.button.offsetBy(dx: -left, dy: 0))
        // Taken back in by the dots' glass, under the first page's dot, at its top.
        #expect(controller.formatFrameForTesting == CGRect(x: column.dots.minX - left, y: column.dots.minY, width: 48, height: 48))
        window.isHidden = true
    }
}
