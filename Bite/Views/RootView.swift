import SwiftUI
import BiteKit

struct RootView: View {
    @Environment(DotStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
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

    var body: some View {
        @Bindable var store = store
        let visiblePage = reportedPage ?? store.selection
        let accent = DotPalette.colors[visiblePage].color

        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            let placement = TopBarPlacement(safeTop: safeArea.top, safeSides: max(safeArea.leading, safeArea.trailing),
                                            width: proxy.size.width + safeArea.leading + safeArea.trailing)
            ZStack(alignment: .top) {
                // A flat, faint wash of the dot's colour behind every page, like tinted paper.
                accent.opacity(PageTint.opacity(dark: colorScheme == .dark))
                    .ignoresSafeArea()
                    .animation(washChangesAtOnce ? nil : .easeInOut(duration: 0.35), value: visiblePage)

                // Full height at all times; the text views handle the keyboard with their own insets.
                // Read as it is now, not as it was when the view was last drawn: two pages reported in
                // a row took the second for no change.
                DotPager(selection: $store.selection, visiblePage: Binding(get: { reportedPage ?? store.selection }, set: { reportedPage = $0 }),
                         isDotBarTouched: isDotBarTouched, topBarMover: topBarMover)
                    .ignoresSafeArea()

                // Up and away with the keys as they come, and back down with them as they go.
                TopBarHost(mover: topBarMover, lift: placement.top + DotSwitcher.height + 8,
                           content: TopBar(selection: $store.selection, visiblePage: visiblePage,
                                           onTap: { washChangesAtOnce = true }, onTouch: { isDotBarTouched = $0 })
                               .environment(store)
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.saveNow() }
        }
    }
}



private struct TopBar: View {
    @Binding var selection: Int
    let visiblePage: Int
    let onTap: () -> Void
    let onTouch: (Bool) -> Void

    var body: some View {
        DotSwitcher(selection: $selection, highlighted: visiblePage, onTap: onTap, onTouch: onTouch)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .trailing) {
                DotMenu(dot: selection)
            }
    }
}
