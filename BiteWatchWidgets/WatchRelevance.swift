import AppIntents
import Foundation
import RelevanceKit
import WidgetKit
import BiteKit

/// What the watch's Smart Stack is told of Bite's widgets, for it to show them first while they
/// matter: a page for a while after it changed, on any device, and the to-dos after a page with
/// to-dos left changed (see `PageRelevance`). Told again whenever Bite writes the pages.
nonisolated enum WatchRelevance {
    /// The pages changed lately, each with the time it stays to the fore.
    static func recentPages() -> [(page: WidgetPage, interval: DateInterval)] {
        guard let shelf, let pages = shelf.read() else { return [] }
        return PageRelevance.recentPages(pages, modified: shelf.readModified() ?? []).compactMap { recent in
            WidgetPage.allCases.indices.contains(recent.page) ? (WidgetPage.allCases[recent.page], recent.interval) : nil
        }
    }

    static func toDosInterval() -> DateInterval? {
        guard let shelf, let pages = shelf.read() else { return nil }
        return PageRelevance.toDosInterval(pages, modified: shelf.readModified() ?? [])
    }

    /// The page widget's settings to show first, and when: what the Smart Stack goes by to bring
    /// in a page widget that isn't in it.
    static func updateIntents() async {
        let intents = recentPages().map { recent in
            RelevantIntent(WatchPageConfiguration(page: recent.page), widgetKind: WidgetKind.page,
                           relevance: .date(interval: recent.interval, kind: .default))
        }
        try? await RelevantIntentManager.shared.updateRelevantIntents(intents)
    }

    private static var shelf: PageShelf? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup).map(PageShelf.init(folder:))
    }
}
