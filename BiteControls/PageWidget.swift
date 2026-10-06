import AppIntents
import SwiftUI
import WidgetKit
import BiteKit

/// A page of Bite on the Home Screen or the Lock Screen. Tapped, it opens Bite on that page. On the
/// Home Screen it turns to the other pages without opening Bite, by the arrow on a small one and
/// the dots on the others, and its checkboxes tick to-dos off.
struct PageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.chenyeni.bite.page", intent: PageWidgetConfiguration.self, provider: PageProvider()) { entry in
            PageWidgetView(entry: entry)
        }
        .configurationDisplayName("Page")
        .description("A page of Bite. Tap a dot, or the arrow, for another.")
        .supportedFamilies(WidgetFamily.bites(byTheClock: false))
        // Margins set by the widget itself: its corner controls sit closer to the edges than the
        // page does (see `WidgetCorner`).
        .contentMarginsDisabled()
    }
}

extension WidgetFamily {
    /// The sizes Bite's widgets come in: all the Home Screen's, a page tall on iOS 27, and the Lock
    /// Screen's, the line by the clock only for the to-dos.
    static func bites(byTheClock: Bool) -> [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                                        .accessoryCircular, .accessoryRectangular]
        if #available(iOS 27, *) { families.insert(.systemExtraLargePortrait, at: 4) }
        if byTheClock { families.append(.accessoryInline) }
        return families
    }
}

/// A page by its dot's colour, for the page a widget shows.
nonisolated enum WidgetPage: String, AppEnum {
    case yellow, orange, red, purple, blue, teal, green

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let caseDisplayRepresentations: [WidgetPage: DisplayRepresentation] = [
        .yellow: "Yellow", .orange: "Orange", .red: "Red", .purple: "Purple", .blue: "Blue", .teal: "Teal", .green: "Green",
    ]

    /// The dot, counting from 0 along the dot bar.
    var dot: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// What a widget is set to show when it's added or edited. On the Home Screen a widget is turned to
/// another page right there, so there's no page to set; on the Lock Screen, where it isn't, there
/// is.
struct PageWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Page"
    static let description: IntentDescription? = IntentDescription("How the widget shows a page.")

    @Parameter(title: "Page", default: .yellow)
    var page: WidgetPage

    @Parameter(title: "Show Title", description: "The page's first line, when it's a heading.", default: true)
    var showsTitle: Bool

    static var parameterSummary: some ParameterSummary {
        When(widgetFamily: .equalTo, .accessoryRectangular) {
            Summary {
                \.$page
                \.$showsTitle
            }
        } otherwise: {
            // The ring shows no title.
            When(widgetFamily: .equalTo, .accessoryCircular) {
                Summary {
                    \.$page
                }
            } otherwise: {
                Summary {
                    \.$showsTitle
                }
            }
        }
    }
}

/// Turns a widget to a page, from its dots or its arrow, without opening Bite. The widget is read
/// again as soon as it's done.
struct TurnPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Widget to Page"
    static let isDiscoverable = false

    /// Which widget, as `ShownPages` names it.
    @Parameter(title: "Widget")
    var widget: String

    @Parameter(title: "Page")
    var page: Int

    init() {}

    init(widget: String, page: Int) {
        self.widget = widget
        self.page = page
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShownPages.set(page, for: widget)
        return .result()
    }
}

/// The page each widget has been turned to. A widget has no name of its own to keep it by, so it's
/// kept by the widget's size and the page it was set to show, when a widget could be: two of one
/// size turn together.
nonisolated enum ShownPages {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: PageShelf.appGroup)
    }

    static func name(family: WidgetFamily, setTo page: WidgetPage) -> String {
        "\(family)-\(page.rawValue)"
    }

    static func page(for widget: String) -> Int? {
        defaults?.object(forKey: "shownPage-\(widget)") as? Int
    }

    static func set(_ page: Int, for widget: String) {
        defaults?.set(page, forKey: "shownPage-\(widget)")
    }
}

/// A widget's page and what the dots need to know of the others.
nonisolated struct PageEntry: TimelineEntry {
    let date: Date
    /// The page shown, counting from 0 along the dot bar.
    let page: Int
    /// The page's lines, without its title where the widget is set to leave it out.
    let glance: PageGlance
    let isEmpty: [Bool]
    /// The widget, as `ShownPages` names it, for its dots and arrow to turn it.
    let widget: String
}

nonisolated struct PageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PageEntry {
        entry(page: 1, pages: SamplePages.markdown, widget: "")
    }

    func snapshot(for configuration: PageWidgetConfiguration, in context: Context) async -> PageEntry {
        entry(for: configuration, in: context)
    }

    /// One entry, as the page is now. Bite has the widgets read again whenever it writes the
    /// pages, and a turn does too, so nothing needs reading on a timer.
    func timeline(for configuration: PageWidgetConfiguration, in context: Context) async -> Timeline<PageEntry> {
        Timeline(entries: [entry(for: configuration, in: context)], policy: .never)
    }

    private func entry(for configuration: PageWidgetConfiguration, in context: Context) -> PageEntry {
        let widget = ShownPages.name(family: context.family, setTo: configuration.page)
        // The Lock Screen's have no dots to turn them: they show the page they're set to.
        let turned = context.family.isOnHomeScreen ? ShownPages.page(for: widget) : nil
        // Before Bite has written the pages, the gallery shows what a page looks like.
        let pages = PageProvider.shelf?.read() ?? SamplePages.markdown
        return entry(page: turned ?? configuration.page.dot, pages: pages, widget: widget, showsTitle: configuration.showsTitle)
    }

    private func entry(page: Int, pages: [String], widget: String, showsTitle: Bool = true) -> PageEntry {
        let glances = pages.map(PageGlance.init(markdown:))
        let page = glances.indices.contains(page) ? page : 0
        let glance = glances[page]
        return PageEntry(date: .now, page: page, glance: showsTitle ? glance : glance.withoutTitle(),
                         isEmpty: glances.map(\.isEmpty), widget: widget)
    }

    private static var shelf: PageShelf? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup).map(PageShelf.init(folder:))
    }
}

/// What a widget shows in the gallery before Bite has written any page.
nonisolated enum SamplePages {
    static let markdown = [
        "# Welcome to Bite\nSeven dots, seven pages for whatever you're juggling right now.\n",
        "# Groceries\n- [ ] Oat milk\n- [ ] Sourdough\n- [x] Eggs\n- [ ] Lemons\n- [ ] Coffee beans\n",
        "# This week\n1. Call the plumber\n2. Book the dentist\n3. Return the library books\n",
        "", "", "", "",
    ]
}
