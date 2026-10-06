import Foundation

/// How a widget turns from page to page, and how it opens Bite on the page it shows.
public enum PageTurns {
    /// The next page with something on it after `page`, going round from the last to the first.
    /// `page` itself when no other page has anything on it.
    public static func next(after page: Int, isEmpty: [Bool]) -> Int {
        guard !isEmpty.isEmpty else { return page }
        for step in 1..<max(isEmpty.count, 1) {
            let candidate = (page + step) % isEmpty.count
            if !isEmpty[candidate] { return candidate }
        }
        return page
    }

    /// The scheme of the links that open Bite on a page, written for Bite alone.
    public static let scheme = "com.chenyeni.bite"

    /// The link that opens Bite on `page`, counted from 0: `com.chenyeni.bite://page/1` for the
    /// first.
    public static func link(to page: Int) -> URL {
        URL(string: "\(scheme)://page/\(page + 1)")!
    }

    /// The page a link opens, or nil for a link that isn't one of these.
    public static func page(openedBy link: URL) -> Int? {
        guard link.scheme == scheme, link.host() == "page", link.pathComponents.count == 2,
              let number = Int(link.pathComponents[1]), (1...DotPalette.count).contains(number) else { return nil }
        return number - 1
    }
}
