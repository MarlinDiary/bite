import SwiftUI
import BiteKit

/// The pages as Bite shows them: a faint wash of the page's colour, the pager, and over it the top
/// bar, the dot bar with a button at either end. Bite's has the "…" button at its end; the share
/// extension's, Cancel and Add, so a page shared to looks just as it does in Bite.
struct PagesView<Leading: View, Trailing: View>: View {
    /// The buttons at the bar's ends, for the page picked.
    let leading: (_ page: Int) -> Leading
    let trailing: (_ page: Int) -> Trailing
    /// Which dots are in their colour (see `DotColors`).
    var dotColors = DotColors.byContent
    /// The page picked: a window's own in Bite, where an iPad can have several (see `PageWindow`);
    /// the store's in the share extension.
    var selection: Binding<Int>?
    @Environment(DotStore.self) private var store
    #if !SHARE_EXTENSION
    @Environment(PageWindow.self) private var pageWindow: PageWindow?
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    /// The page on screen, as the pager last reported it. The dot bar and the wash follow it, so
    /// during a swipe they change as the next page takes over the screen.
    @State private var reportedPage: Int?
    /// Set by a tap on a dot, whose page opens at once: the wash then changes with it. After a
    /// swipe, or while sliding along the dots, the wash fades over instead.
    @State private var washChangesAtOnce = false
    /// Set while a finger is on the dot bar.
    @State private var isDotBarTouched = false
    /// Moves the dot bar up out of the way of the keys on a phone on its side, for the pager.
    @State private var topBarMover = TopBarMover()
    /// Moves the dots down the status bar's column with the keys, on iPhone Duo.
    @State private var columnMover = ColumnMover()
    /// How far in from the window's start the system's window controls reach, on an iPad's window
    /// that isn't full screen (see `WindowControlsReader`).
    @State private var windowControls: CGFloat = 0
    /// The side the system puts its bars down, on iPhone Duo (see `BarEdgeReader`).
    @State private var barEdge: HorizontalEdge?
    /// What the system covers of the window, its status bar and camera, on iPhone Duo (see
    /// `OcclusionReader`).
    @State private var occlusions: [CGRect] = []

    var body: some View {
        @Bindable var store = store
        let selection = selection ?? $store.selection
        let visiblePage = reportedPage ?? selection.wrappedValue
        let accent = DotPalette.colors[visiblePage].color

        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            let width = proxy.size.width + safeArea.leading + safeArea.trailing
            let placement = TopBarPlacement(safeTop: safeArea.top, safeSides: max(safeArea.leading, safeArea.trailing), width: width)
            let startFits = TopBarPlacement.startButtonFits(width: width, side: placement.side, windowControls: windowControls)
            let size = CGSize(width: width, height: proxy.size.height + safeArea.top + safeArea.bottom)
            #if SHARE_EXTENSION
            let column: SideColumn? = nil
            #else
            let column = SideColumn(safeTop: safeArea.top, safeLeading: safeArea.leading, safeTrailing: safeArea.trailing,
                                    size: size, occlusions: occlusions, bigScreen: isBigScreen, folds: folds(proxy),
                                    barEdge: barEdge, screenFolds: screenFolds(proxy))
            #endif
            ZStack(alignment: .top) {
                WindowControlsReader { windowControls = $0 }
                    .ignoresSafeArea()
                #if !SHARE_EXTENSION
                BarEdgeReader { barEdge = $0 }
                    .ignoresSafeArea()
                OcclusionReader { occlusions = $0 }
                    .ignoresSafeArea()
                #endif

                // A flat, faint wash of the dot's colour behind every page, like tinted paper.
                accent.opacity(PageTint.opacity(dark: colorScheme == .dark))
                    .ignoresSafeArea()
                    .animation(washChangesAtOnce ? nil : .easeInOut(duration: 0.35), value: visiblePage)

                // Full height at all times; the text views handle the keyboard with their own insets.
                // Read as it is now, not as it was when the view was last drawn: two pages reported in
                // a row took the second for no change.
                DotPager(selection: selection, visiblePage: Binding(get: { reportedPage ?? selection.wrappedValue }, set: { reportedPage = $0 }),
                         isDotBarTouched: isDotBarTouched, topBarMover: topBarMover, columnMover: columnMover)
                    .ignoresSafeArea()

                if let column {
                    // Down the status bar's column, on iPhone Duo: the dots midway between the
                    // status bar and the "…" button at its foot, drawn in to the page's own dot as
                    // the keys come up over the button, the button under it (see `SideColumn`).
                    ColumnHost(mover: columnMover, column: column, height: size.height,
                               dots: DotSwitcher(selection: selection, highlighted: visiblePage,
                                                 onTap: { washChangesAtOnce = true }, onTouch: { isDotBarTouched = $0 },
                                                 axis: .vertical, thickness: SideColumn.glass, glass: false)
                                   .environment(store)
                                   .environment(\.dotColors, dotColors)
                                   .tint(accent),
                               dot: PageDot(page: visiblePage,
                                            step: { by in
                                                washChangesAtOnce = true
                                                selection.wrappedValue = SideColumn.page(selection.wrappedValue, steppedBy: by)
                                            },
                                            onTouch: { isDotBarTouched = $0 }),
                               page: visiblePage,
                               pageIsColoured: dotColors.isColoured(visiblePage, isSelected: true, isEmpty: store.isEmpty),
                               menu: trailing(selection.wrappedValue)
                                   .environment(\.barButtonSize, SideColumn.glass)
                                   .environment(store)
                                   #if !SHARE_EXTENSION
                                   .environment(pageWindow)
                                   #endif
                                   .tint(accent),
                               tint: accent)
                        .frame(width: column.frame.width, height: size.height)
                        .position(x: column.frame.midX, y: size.height / 2)
                        .ignoresSafeArea()
                } else {
                    // Up and away with the keys as they come, and back down with them as they go.
                    TopBarHost(mover: topBarMover, lift: placement.top + DotSwitcher.height + 8,
                               content: TopBar(selection: selection, visiblePage: visiblePage,
                                               onTap: { washChangesAtOnce = true }, onTouch: { isDotBarTouched = $0 },
                                               showsLeading: startFits,
                                               leading: leading(selection.wrappedValue), trailing: trailing(selection.wrappedValue))
                                   .environment(store)
                                   #if !SHARE_EXTENSION
                                   .environment(pageWindow)
                                   #endif
                                   .environment(\.dotColors, dotColors)
                                   .tint(accent))
                        .frame(height: DotSwitcher.height)
                        .padding(.top, placement.top)
                        .padding(.horizontal, placement.side)
                        .ignoresSafeArea()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .tint(accent)
        .onChange(of: visiblePage) { washChangesAtOnce = false }
    }

    /// Where the screen's folded part way, on the screen.
    private func folds(_ proxy: GeometryProxy) -> [CGRect] {
        guard #available(iOS 27.1, *) else { return [] }
        let origin = CGPoint(x: proxy.safeAreaInsets.leading, y: proxy.safeAreaInsets.top)
        return proxy.reservedRegions(kind: .division).filter(\.isActive).map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) }
    }

    /// Whether the screen folds, flat or not: iPhone Duo's inner display, where the system marks the
    /// fold, whole or beside another app.
    private func screenFolds(_ proxy: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    /// Whether the screen's a phone's as big as an iPad's: iPhone Duo's inner one (see `SideColumn`).
    private var isBigScreen: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && widthClass == .regular && heightClass == .regular
    }
}

/// A button over the page on screen's dot, all the dots show drawn in while the keys are up, down
/// iPhone Duo's column (see `SideColumn`): the dots show it, as they're still there under the glass
/// (user, 2026-10-19). The finger lifting on it, held or not, opens the next page at once, the last
/// one's next the first; pressed, the glass answers. Like a finger on the dot bar it ticks as the
/// page changes, and the keys go over to that page.
private struct PageDot: View {
    let page: Int
    /// Opens the page `by` pages on, round from the last to the first: 1 the next, -1 the one
    /// before.
    let step: (_ by: Int) -> Void
    /// Called with true as a finger comes down on it, and with false once it's lifted.
    let onTouch: (Bool) -> Void
    /// Whether a finger is down on it. Unlike `onEnded`, this also ends when the system takes the
    /// touch away.
    @GestureState private var isTouched = false

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(.circle)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isTouched) { _, state, _ in state = true }
                        .onEnded { value in
                            // Lifted on it, or near: a finger that slid well off it has let go.
                            let near = CGRect(origin: .zero, size: proxy.size).insetBy(dx: -24, dy: -24)
                            if near.contains(value.location) { step(1) }
                        }
                )
        }
        .onChange(of: isTouched) { _, isTouched in
            onTouch(isTouched)
        }
        .accessibilityElement()
        .accessibilityLabel("\(DotPalette.colors[page].localizedName) dot")
        .accessibilityAddTraits([.isButton, .isSelected])
        .accessibilityAction { step(1) }
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }
}

extension EnvironmentValues {
    /// How big the bar's round buttons are: the dot bar's height, but in the status bar's column
    /// on iPhone Duo, where the system's glass is thicker (see `SideColumn`).
    @Entry var barButtonSize: CGFloat = DotSwitcher.height
}

private struct TopBar<Leading: View, Trailing: View>: View {
    @Binding var selection: Int
    let visiblePage: Int
    let onTap: () -> Void
    let onTouch: (Bool) -> Void
    /// Off where the button at the start doesn't clear the dots (see
    /// `TopBarPlacement.startButtonFits`).
    let showsLeading: Bool
    let leading: Leading
    let trailing: Trailing

    var body: some View {
        DotSwitcher(selection: $selection, highlighted: visiblePage, onTap: onTap, onTouch: onTouch)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if showsLeading { leading }
            }
            .overlay(alignment: .trailing) {
                trailing
            }
    }
}
