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

    var body: some View {
        @Bindable var store = store
        let visiblePage = reportedPage ?? store.selection
        let accent = DotPalette.colors[visiblePage].color

        ZStack(alignment: .top) {
            // A flat, faint wash of the dot's colour behind every page, like tinted paper.
            accent.opacity(PageTint.opacity(dark: colorScheme == .dark))
                .ignoresSafeArea()
                .animation(washChangesAtOnce ? nil : .easeInOut(duration: 0.35), value: visiblePage)

            // Full height at all times; the text views handle the keyboard with their own insets.
            DotPager(selection: $store.selection, visiblePage: Binding(get: { visiblePage }, set: { reportedPage = $0 }),
                     isDotBarTouched: isDotBarTouched)
                .ignoresSafeArea()

            TopBar(selection: $store.selection, visiblePage: visiblePage, onTap: { washChangesAtOnce = true },
                   onTouch: { isDotBarTouched = $0 })
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
            .padding(.horizontal, 16)
            .padding(.top, 2)
    }
}
