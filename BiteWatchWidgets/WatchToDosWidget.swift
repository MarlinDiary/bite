import SwiftUI
import WidgetKit
import BiteKit

/// Every to-do still to do, from all seven pages: how many, in Bite's ring; the first few in a
/// rectangle, as in the Smart Stack; the count by the clock; or the next one along a corner's
/// edge. With none left, it says so. Tapped, it opens Bite on the first one's page.
struct WatchToDosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.chenyeni.bite.todos", provider: WatchToDosProvider()) { entry in
            WatchToDosView(entry: entry)
        }
        .configurationDisplayName("To-Dos")
        .description("The to-dos still to do on every page.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

/// A to-do still to do, and the page it's on.
nonisolated struct WatchToDo: Hashable, Identifiable {
    let page: Int
    let block: Int
    let text: String

    var id: String {
        "\(page)-\(block)"
    }
}

nonisolated struct WatchToDosEntry: TimelineEntry {
    let date: Date
    /// Every to-do still to do, page by page along the dot bar, in each page's order.
    let toDos: [WatchToDo]
}

nonisolated struct WatchToDosProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchToDosEntry {
        entry(at: .now, pages: SamplePages.markdown)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchToDosEntry) -> Void) {
        completion(entry(at: .now, pages: SamplePages.orShelf()))
    }

    /// As the pages are now: Bite has the widgets read again whenever it writes them. With nothing
    /// left to do, the wish changes with the time of day, the day after too.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchToDosEntry>) -> Void) {
        let pages = SamplePages.orShelf()
        let now = entry(at: .now, pages: pages)
        guard now.toDos.isEmpty else {
            completion(Timeline(entries: [now], policy: .never))
            return
        }
        let later = TimeOfDay.changes(after: now.date).map { entry(at: $0, pages: pages) }
        completion(Timeline(entries: [now] + later, policy: .atEnd))
    }

    private func entry(at date: Date, pages: [String]) -> WatchToDosEntry {
        let toDos = pages.enumerated().flatMap { page, markdown in
            PageGlance(markdown: markdown).lines
                .filter { $0.kind == .todo && !$0.isChecked }
                .map { WatchToDo(page: page, block: $0.block, text: $0.text) }
        }
        return WatchToDosEntry(date: date, toDos: toDos)
    }
}

struct WatchToDosView: View {
    let entry: WatchToDosEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(entry.toDos.first.map { PageTurns.link(to: $0.page) })
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        let count = entry.toDos.count
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                ToDoCount(count: count)
            }
        case .accessoryCorner:
            ToDoCount(count: count, share: 0.8)
                .widgetLabel(entry.toDos.first?.text ?? "All done")
        case .accessoryInline:
            Label {
                Text(count == 0 ? "All done" : count == 1 ? "1 to-do" : "\(count) to-dos")
            } icon: {
                Image("bite.ring")
            }
        default:
            if entry.toDos.isEmpty {
                // Bite's orange dot, its icon's, as the full stop.
                DotStatement(title: "All done", ink: DotPalette.colors[1], line: TimeOfDay.wish(at: entry.date))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.toDos.prefix(3)) { toDo in
                        HStack(spacing: 6) {
                            Checkbox(isChecked: false, ink: DotPalette.colors[toDo.page], size: 14, scale: 14 / 19)
                            Text(toDo.text)
                                .font(.system(size: 15))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// How many to-dos there are, in Bite's ring, in its icon's orange; a tick when there are none.
private struct ToDoCount: View {
    let count: Int
    var share: CGFloat = 0.64

    var body: some View {
        WatchRing(ink: DotPalette.colors[1], share: share) { diameter in
            if count > 0 {
                // As big as the ring's hole holds: at the phone's size it read small on a watch.
                Text("\(count)")
                    .font(.system(size: diameter * 0.42, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .frame(width: diameter * 0.52)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.3, weight: .bold))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(count == 0 ? "Nothing to do" : count == 1 ? "1 to-do" : "\(count) to-dos")
    }
}
