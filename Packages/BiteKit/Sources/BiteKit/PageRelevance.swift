import Foundation

/// When a page is worth showing before the others, as the watch's Smart Stack does: for a while
/// after it changed, on any device, as a list written on the phone is wanted at the shops.
public enum PageRelevance {
    /// How long a page stays to the fore after it changed.
    public static let lasts: TimeInterval = 3 * 60 * 60

    /// The pages with something on them that changed lately, along the dot bar, each with the time
    /// it stays to the fore.
    public static func recentPages(_ pages: [String], modified: [Date?], now: Date = .now) -> [(page: Int, interval: DateInterval)] {
        pages.indices.compactMap { page in
            guard !PageGlance(markdown: pages[page]).isEmpty,
                  let interval = interval(after: modified.indices.contains(page) ? modified[page] : nil, now: now) else { return nil }
            return (page, interval)
        }
    }

    /// The time the to-dos stay to the fore: after the latest change to a page with to-dos still to
    /// do. Nil with none to do, or none of their pages changed lately.
    public static func toDosInterval(_ pages: [String], modified: [Date?], now: Date = .now) -> DateInterval? {
        let changes = pages.indices.compactMap { page -> Date? in
            guard PageGlance(markdown: pages[page]).toDos.open > 0, modified.indices.contains(page) else { return nil }
            return modified[page]
        }
        return interval(after: changes.max(), now: now)
    }

    /// From a change to `lasts` after it, while that's still to come.
    private static func interval(after change: Date?, now: Date) -> DateInterval? {
        guard let change else { return nil }
        let end = change.addingTimeInterval(lasts)
        return end > now ? DateInterval(start: change, end: end) : nil
    }
}
