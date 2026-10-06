import AppIntents
import SwiftUI
import WidgetKit
import BiteKit

/// Every to-do still to do, from all seven pages, each with its page's colour. Ticked off here, it
/// goes from the list, and from the page it's on. With none, it says so.
struct ToDosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.chenyeni.bite.todos", provider: ToDosProvider()) { entry in
            ToDosView(entry: entry)
        }
        .configurationDisplayName("To-Dos")
        .description("The to-dos still to do on every page. Tick one off right here.")
        .supportedFamilies(WidgetFamily.homeScreen + WidgetFamily.lockScreen(byTheClock: true))
        .contentMarginsDisabled()
    }
}

/// A to-do still to do, and the page it's on.
nonisolated struct OpenToDo: Hashable, Identifiable {
    let page: Int
    let line: PageGlance.Line

    /// The same before it's ticked off as after: the checkbox tapped is the one the system goes on
    /// showing ticked while the tick is made. Known by whether it was done, the row was a new one
    /// once it was, and the old one's box stayed as it was tapped.
    var id: String {
        "\(page)-\(line.block)-\(line.text)"
    }
}

nonisolated struct ToDosEntry: TimelineEntry {
    let date: Date
    /// Every to-do still to do, page by page along the dot bar, in each page's order.
    let toDos: [OpenToDo]

    /// How many are still to do, leaving out any just ticked off, shown a moment longer.
    var open: Int {
        toDos.count { !$0.line.isChecked }
    }
}

nonisolated struct ToDosProvider: TimelineProvider {
    /// How long a to-do ticked off in the widget stays, ticked, before it goes, as Reminders' do.
    static let ticked: TimeInterval = 2

    func placeholder(in context: Context) -> ToDosEntry {
        entry(at: .now, pages: SamplePages.markdown, shown: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ToDosEntry) -> Void) {
        completion(entry(at: .now, pages: Self.shelf?.read() ?? SamplePages.markdown, shown: []))
    }

    /// As the pages are now, to-dos just ticked off here among them a moment, ticked, and then
    /// without them. Bite has the widgets read again whenever it writes the pages.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ToDosEntry>) -> Void) {
        let now = Date.now
        let pages = Self.shelf?.read() ?? SamplePages.markdown
        let shown = Self.shelf?.shownTicks(since: now.addingTimeInterval(-Self.ticked)).filter(\.tick.done) ?? []
        var entries = [entry(at: now, pages: pages, shown: shown.map(\.tick))]
        if let last = shown.map(\.date).max() {
            entries.append(entry(at: last.addingTimeInterval(Self.ticked), pages: pages, shown: []))
        }
        // With nothing left to do, the wish changes with the time of day, the day after too.
        guard let settled = entries.last, settled.toDos.isEmpty else {
            completion(Timeline(entries: entries, policy: .never))
            return
        }
        entries += TimeOfDay.changes(after: settled.date).map { entry(at: $0, pages: pages, shown: []) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static var shelf: PageShelf? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup).map(PageShelf.init(folder:))
    }

    private func entry(at date: Date, pages: [String], shown: [PageTick]) -> ToDosEntry {
        let toDos = pages.enumerated().flatMap { page, markdown in
            PageGlance(markdown: markdown).lines
                .filter { line in
                    line.kind == .todo && (!line.isChecked || shown.contains { $0.page == page && $0.text == line.text })
                }
                .map { OpenToDo(page: page, line: $0) }
        }
        return ToDosEntry(date: date, toDos: toDos)
    }
}

/// The to-dos, as many as fit whole, in the system's own margins, as Reminders' are. With none
/// left, "All done". On the Home Screen they're on the launch screen's colour,
/// the one closest to all seven pages' tints, as they come from all seven.
struct ToDosView: View {
    let entry: ToDosEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        content
            .widgetURL(entry.toDos.first.map { PageTurns.link(to: $0.page) })
            .modifier(OwnBackground(isOnHomeScreen: family.isOnHomeScreen) { Color("LaunchBackground") })
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            ToDoCount(count: entry.open)
        case .accessoryInline:
            Label {
                Text(entry.open == 0 ? "All done" : entry.open == 1 ? "1 to-do" : "\(entry.open) to-dos")
            } icon: {
                Image("bite.ring")
            }
        case .accessoryRectangular:
            if entry.toDos.isEmpty {
                AllDone(date: entry.date)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.toDos.prefix(3)) { toDo in
                        HStack(spacing: 6) {
                            Checkbox(isChecked: false, ink: DotPalette.colors[toDo.page], size: 12, scale: 0.63)
                            Text(toDo.line.text).font(.system(size: 14)).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        #endif
        default:
            let isEmpty = entry.toDos.isEmpty
            ZStack(alignment: .topLeading) {
                if isEmpty {
                    AllDone(date: entry.date)
                        .transition(.opacity)
                } else {
                    ToDoList(toDos: entry.toDos, opensPages: family != .systemSmall)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(margins)
            .animation(.easeOut(duration: 0.5), value: isEmpty)
        }
    }
}

/// The sizes of a to-do's row.
nonisolated enum ToDoMetrics {
    static let font: CGFloat = 15
    static let box: CGFloat = 17
    static let boxGap: CGFloat = 9
    static let spacing: CGFloat = 9
    static var height: CGFloat { max(box, GlanceMetrics.row(font)) }
}

/// As many to-dos as fit, whole. The rest wait their turn, coming up as these are ticked off.
private struct ToDoList: View {
    let toDos: [OpenToDo]
    let opensPages: Bool

    var body: some View {
        GeometryReader { proxy in
            let pitch = ToDoMetrics.height + ToDoMetrics.spacing
            let rows = max(1, Int(((proxy.size.height + ToDoMetrics.spacing) / pitch).rounded(.down)))
            VStack(alignment: .leading, spacing: ToDoMetrics.spacing) {
                ForEach(toDos.prefix(rows)) { toDo in
                    ToDoRow(toDo: toDo, opensPage: opensPages)
                }
            }
        }
    }
}

/// A to-do with its page's checkbox, which ticks it off. Its text opens Bite on its page, where a
/// widget lets a part of it open a page of its own: a small widget opens as a whole.
private struct ToDoRow: View {
    let toDo: OpenToDo
    let opensPage: Bool

    var body: some View {
        let ink = DotPalette.colors[toDo.page]
        let done = toDo.line.isChecked
        HStack(spacing: ToDoMetrics.boxGap) {
            Toggle(isOn: done,
                   intent: ToggleToDoIntent(PageTick(page: toDo.page, block: toDo.line.block, text: toDo.line.text, done: !done))) {
                EmptyView()
            }
            .toggleStyle(CheckboxStyle(ink: ink, size: ToDoMetrics.box, scale: ToDoMetrics.box / 19))
            text
        }
        .frame(height: ToDoMetrics.height)
    }

    @ViewBuilder
    private var text: some View {
        let done = toDo.line.isChecked
        let label = Text(toDo.line.text)
            .font(.system(size: ToDoMetrics.font))
            .foregroundStyle(done ? Color.systemSecondaryLabel : Color.systemLabel)
            .strikethrough(done)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        if opensPage {
            Link(destination: PageTurns.link(to: toDo.page)) { label }
        } else {
            label
        }
    }
}

/// With nothing left to do: "All done", its full stop the dot of Bite's icon, and a wish for the
/// time of day.
private struct AllDone: View {
    let date: Date

    var body: some View {
        DotStatement(title: "All done", ink: DotPalette.colors[1], line: TimeOfDay.wish(at: date))
    }
}

#if os(iOS)
/// How many to-dos there are, in Bite's ring, on the Lock Screen.
private struct ToDoCount: View {
    let count: Int

    var body: some View {
        let diameter: CGFloat = 46
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .strokeBorder(lineWidth: diameter * 160 / 770)
                .frame(width: diameter, height: diameter)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.5)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
            }
        }
        .widgetAccentable()
        .accessibilityElement()
        .accessibilityLabel(count == 0 ? "Nothing to do" : count == 1 ? "1 to-do" : "\(count) to-dos")
    }
}
#endif
