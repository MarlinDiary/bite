import SwiftUI
import BiteKit

/// The seven pages, a screen each, turned with the Digital Crown as the system's own apps' pages
/// are on the watch: each shows as much of its page as fits, on its dot's colour, its heading as
/// its first line, as in Bite, with no title over it (user, 2026-10-09). The time stays: an app
/// can't hide it. A tap opens the whole page. Opened from a widget on the watch face, it's turned
/// to the widget's page.
struct PagesView: View {
    @Environment(DotStore.self) private var store
    /// The page opened, if one is.
    @State private var path: [Int] = []
    /// Counts the times a widget opened Bite, for the pages to start afresh on the widget's page.
    @State private var linksOpened = 0

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            TabView(selection: $store.selection) {
                ForEach(DotPalette.colors.indices, id: \.self) { dot in
                    PageCard(dot: dot)
                        .tag(dot)
                }
            }
            .tabViewStyle(.verticalPage)
            // Made anew on the page a widget opens, rather than scrolled to it.
            .id(linksOpened)
            .navigationDestination(for: Int.self) { dot in
                PageView(dot: dot)
            }
        }
        .onOpenURL { link in
            guard let page = PageTurns.page(openedBy: link) else { return }
            // Right after this, as Bite launches, the pages turn back to the page they're being
            // laid out on, the one Bite was last on: so turned once that's done.
            Task {
                path = []
                store.open(dot: page)
                linksOpened += 1
            }
        }
    }
}

/// A page, as much of it as fits on a screen, its lines fading out where it goes on.
private struct PageCard: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var textSize = WatchLook.textSize

    var body: some View {
        let ink = DotPalette.colors[dot]
        // Read for the page's changes, which come in as other devices' do.
        let _ = store.revisions[dot]
        let glance = PageGlance(markdown: store.markdown[dot])
        NavigationLink(value: dot) {
            Group {
                if glance.isEmpty {
                    // In the middle of the room the system keeps clear, not of the whole screen.
                    DotStatement(title: ink.name, ink: ink, line: WatchLook.emptyLine(waitingForICloud: store.isWaitingForICloud),
                                 sizes: WatchLook.emptySizes)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PageGlanceView(glance: glance, page: dot, ink: ink, metrics: WatchLook.metrics(textSize: textSize),
                                   safeBottom: PageLines.bottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Down to the screen's bottom edge, as a widget's page goes: stopped short
                        // of it, above the room the system keeps there, too few lines showed (user,
                        // 2026-10-09).
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scenePadding(.horizontal)
        .containerBackground(WatchLook.background(ink), for: .tabView)
    }
}
