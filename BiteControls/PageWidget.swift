import AppIntents
import SwiftUI
import WidgetKit
import BiteKit

/// One page of Bite, the one it's set to, with nothing to turn it by: on the Home Screen, the Mac's
/// desktop or the Lock Screen. Tapped, it opens Bite on the page, and its checkboxes tick to-dos
/// off.
struct SinglePageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.chenyeni.bite.singlepage", intent: SinglePageConfiguration.self,
                               provider: SinglePageProvider()) { entry in
            PageWidgetView(entry: entry, turns: false)
        }
        .configurationDisplayName("Page")
        .description("One page of Bite, the one you choose.")
        .supportedFamilies(WidgetFamily.homeScreen + WidgetFamily.lockScreen(byTheClock: false))
        .contentMarginsDisabled()
    }
}

/// Bite's pages on the Home Screen or the Mac's desktop, turned to another without opening Bite: by
/// the arrow on a small one, the dots on the others. Tapped, it opens Bite on the page it shows,
/// and its checkboxes tick to-dos off.
struct PageWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.chenyeni.bite.page", intent: PageWidgetConfiguration.self, provider: PageProvider()) { entry in
            PageWidgetView(entry: entry)
        }
        .configurationDisplayName("Pages")
        .description("Bite's pages. Tap a dot, or the arrow, for another.")
        .supportedFamilies(WidgetFamily.homeScreen)
        // Margins set by the widget itself: its corner controls sit closer to the edges than the
        // page does (see `WidgetCorner`).
        .contentMarginsDisabled()
    }
}

extension WidgetFamily {
    /// The Home Screen's sizes, or the Mac desktop's, with one as tall as a page on iOS and macOS 27.
    static var homeScreen: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27, macOS 27, *) { families.append(.systemExtraLargePortrait) }
        return families
    }

    /// The Lock Screen's, the line by the clock only for the to-dos. A Mac has none.
    static func lockScreen(byTheClock: Bool) -> [WidgetFamily] {
        #if os(iOS)
        byTheClock ? [.accessoryCircular, .accessoryRectangular, .accessoryInline] : [.accessoryCircular, .accessoryRectangular]
        #else
        []
        #endif
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

/// What a turning widget is set to show. It's turned to another page right there, so there's no
/// page to set: `page` is where one set to a page before then starts.
struct PageWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Page"
    static let description: IntentDescription? = IntentDescription("How the widget shows a page.")

    @Parameter(title: "Page", default: .yellow)
    var page: WidgetPage

    @Parameter(title: "Show Title", description: "The page's first line, when it's a heading.", default: true)
    var showsTitle: Bool

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$showsTitle
        }
    }
}

/// What a single page's widget is set to show: its page, and whether with its title.
struct SinglePageConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Page"
    static let description: IntentDescription? = IntentDescription("The page the widget shows.")

    @Parameter(title: "Page", default: .yellow)
    var page: WidgetPage

    @Parameter(title: "Show Title", description: "The page's first line, when it's a heading.", default: true)
    var showsTitle: Bool

    static var parameterSummary: some ParameterSummary {
        // The ring on the Lock Screen shows no title.
        When(widgetFamily: .equalTo, .accessoryCircular) {
            Summary {
                \.$page
            }
        } otherwise: {
            Summary {
                \.$page
                \.$showsTitle
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
        PageEntry(page: 1, pages: SamplePages.markdown, widget: "")
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
        return PageEntry(page: ShownPages.page(for: widget) ?? configuration.page.dot, pages: SamplePages.orShelf(),
                         widget: widget, showsTitle: configuration.showsTitle)
    }
}

/// A single page's widget: the page it's set to, as it is now.
nonisolated struct SinglePageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PageEntry {
        PageEntry(page: 1, pages: SamplePages.markdown, widget: "")
    }

    func snapshot(for configuration: SinglePageConfiguration, in context: Context) async -> PageEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SinglePageConfiguration, in context: Context) async -> Timeline<PageEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SinglePageConfiguration) -> PageEntry {
        PageEntry(page: configuration.page.dot, pages: SamplePages.orShelf(), widget: "", showsTitle: configuration.showsTitle)
    }
}

nonisolated extension PageEntry {
    /// `page` of `pages`, without its title if so set, as the widget shows it now.
    init(page: Int, pages: [String], widget: String, showsTitle: Bool = true) {
        let glances = pages.map(PageGlance.init(markdown:))
        let page = glances.indices.contains(page) ? page : 0
        let glance = glances[page]
        self.init(date: .now, page: page, glance: showsTitle ? glance : glance.withoutTitle(),
                  isEmpty: glances.map(\.isEmpty), widget: widget)
    }
}

/// What a widget shows in the gallery before Bite has written any page.
nonisolated enum SamplePages {
    /// The pages as Bite last wrote them for the widgets, or these, before it has.
    static func orShelf() -> [String] {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup)
            .flatMap { PageShelf(folder: $0).read() } ?? markdown
    }

    static let markdown = [
        "# Welcome to Bite\nSeven dots, seven pages for whatever you're juggling right now.\n",
        "# Groceries\n- [ ] Oat milk\n- [ ] Sourdough\n- [x] Eggs\n- [ ] Lemons\n- [ ] Coffee beans\n",
        "# This week\n1. Call the plumber\n2. Book the dentist\n3. Return the library books\n",
        "", "", "", "",
    ]
}
