import AppIntents
import RelevanceKit
import SwiftUI
import WidgetKit
import BiteKit

/// One page of Bite on the watch face, the one it's set to: its first lines in a rectangle, as in
/// the Smart Stack, where it's on its page's colour, as in Bite on the watch; or Bite's ring in the
/// page's colour, in a circle, or in a corner with the page's first line along the edge. Tapped,
/// it opens Bite on the page.
struct WatchPageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.page, intent: WatchPageConfiguration.self,
                               provider: WatchPageProvider()) { entry in
            WatchPageView(entry: entry)
        }
        .configurationDisplayName("Page")
        .description("One page of Bite, the one you choose.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner])
        // The page goes on past the bottom margin, as in Bite's other widgets (see `WatchPageView`).
        .contentMarginsDisabled()
    }
}

/// The page a widget on the watch shows.
struct WatchPageConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Page"
    static let description: IntentDescription? = IntentDescription("The page the widget shows.")

    @Parameter(title: "Page", default: .yellow)
    var page: WidgetPage

    init() {}

    init(page: WidgetPage) {
        self.page = page
    }
}

nonisolated struct WatchPageEntry: TimelineEntry {
    let date: Date
    /// The page shown, counting from 0 along the dot bar.
    let page: Int
    let glance: PageGlance
}

nonisolated struct WatchPageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchPageEntry {
        entry(page: 1, pages: SamplePages.markdown)
    }

    func snapshot(for configuration: WatchPageConfiguration, in context: Context) async -> WatchPageEntry {
        entry(page: configuration.page.dot, pages: SamplePages.orShelf())
    }

    /// One entry, as the page is now. Bite has the widgets read again whenever it writes the
    /// pages, so nothing needs reading on a timer.
    func timeline(for configuration: WatchPageConfiguration, in context: Context) async -> Timeline<WatchPageEntry> {
        await WatchRelevance.updateIntents()
        return Timeline(entries: [entry(page: configuration.page.dot, pages: SamplePages.orShelf())], policy: .never)
    }

    /// A page that changed lately comes first in the Smart Stack (see `WatchRelevance`).
    func relevance() async -> WidgetRelevance<WatchPageConfiguration> {
        await WatchRelevance.updateIntents()
        return WidgetRelevance(WatchRelevance.recentPages().map { recent in
            WidgetRelevanceAttribute(configuration: WatchPageConfiguration(page: recent.page),
                                     context: .date(interval: recent.interval, kind: .default))
        })
    }

    /// A watch face offers a widget's settings as choices to pick from: a page each.
    func recommendations() -> [AppIntentRecommendation<WatchPageConfiguration>] {
        WidgetPage.allCases.map { page in
            AppIntentRecommendation(intent: WatchPageConfiguration(page: page), description: DotPalette.colors[page.dot].localizedName)
        }
    }

    private func entry(page: Int, pages: [String]) -> WatchPageEntry {
        let page = pages.indices.contains(page) ? page : 0
        return WatchPageEntry(date: .now, page: page, glance: PageGlance(markdown: pages[page]))
    }
}

struct WatchPageView: View {
    let entry: WatchPageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    private var ink: DotColor {
        DotPalette.colors[entry.page]
    }

    var body: some View {
        content
            .widgetURL(PageTurns.link(to: entry.page))
            .containerBackground(WatchLook.background(ink), for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                WatchRing(ink: ink)
            }
            .accessibilityElement()
            .accessibilityLabel("\(ink.localizedName) page")
        case .accessoryCorner:
            WatchRing(ink: ink, share: 0.95)
                .widgetLabel(entry.glance.title ?? ink.localizedName)
        default:
            if entry.glance.isEmpty {
                DotStatement(title: ink.localizedName, ink: ink, line: WatchLook.emptyLine)
                    .padding(margins)
            } else {
                // Down to the bottom edge, the next line fading under it, as in Bite's other
                // widgets: kept above the bottom margin, the Smart Stack showed a line less.
                PageGlanceView(glance: entry.glance, page: entry.page, ink: ink,
                               metrics: GlanceMetrics(scale: 0.88, flatHeadings: true), ticks: false,
                               safeBottom: PageLines.bottom)
                    .padding(EdgeInsets(top: margins.top, leading: margins.leading, bottom: 0, trailing: margins.trailing))
            }
        }
    }
}
