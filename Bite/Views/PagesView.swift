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
    /// How far in from the window's start the system's window controls reach, on an iPad's window
    /// that isn't full screen (see `WindowControlsReader`).
    @State private var windowControls: CGFloat = 0

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
            ZStack(alignment: .top) {
                WindowControlsReader { windowControls = $0 }
                    .ignoresSafeArea()

                // A flat, faint wash of the dot's colour behind every page, like tinted paper.
                accent.opacity(PageTint.opacity(dark: colorScheme == .dark))
                    .ignoresSafeArea()
                    .animation(washChangesAtOnce ? nil : .easeInOut(duration: 0.35), value: visiblePage)

                // Full height at all times; the text views handle the keyboard with their own insets.
                // Read as it is now, not as it was when the view was last drawn: two pages reported in
                // a row took the second for no change.
                DotPager(selection: selection, visiblePage: Binding(get: { reportedPage ?? selection.wrappedValue }, set: { reportedPage = $0 }),
                         isDotBarTouched: isDotBarTouched, topBarMover: topBarMover)
                    .ignoresSafeArea()

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
        .background(Color(uiColor: .systemBackground))
        .tint(accent)
        .onChange(of: visiblePage) { washChangesAtOnce = false }
    }
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
