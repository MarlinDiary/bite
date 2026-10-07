import Foundation
import BiteKit

/// Bite's pages as its command line tool reaches them: read from the copy Bite keeps for its
/// extensions, and changed by Bite itself, which puts each change together with whatever was typed
/// in Bite meanwhile, as it does a page shared to it (see `PageShare`).
public protocol PageAccess: Sendable {
    /// Every page's Markdown, along the dot bar.
    func pages() async throws -> [String]
    /// When each page last changed, where known.
    func modified() async -> [Date?]
    /// The page Bite shows, or was last on.
    func shownPage() async -> Int?
    /// Has Bite change `page` from `before`, the page as read, to `after`: the page as Bite then has
    /// it, or nil when Bite hasn't taken the change in yet, which it does as it next runs.
    func change(page: Int, from before: String, to after: String) async throws -> String?
    /// Has Bite show `page`.
    func open(page: Int) async throws
}

/// What went wrong, said so that a person, or an AI, can put it right.
public struct CommandError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// A page named on the command line or by an AI: by its colour, by its number along the dot bar
/// from 1, or as "current", the page Bite shows.
public enum PageReference: Equatable, Sendable {
    /// Counting from 0 along the dot bar.
    case page(Int)
    case shown

    public init(_ name: String) throws {
        let name = name.trimmingCharacters(in: .whitespaces).lowercased()
        if ["current", "shown", "this"].contains(name) {
            self = .shown
        } else if let number = Int(name), (1...DotPalette.count).contains(number) {
            self = .page(number - 1)
        } else if let index = DotPalette.colors.firstIndex(where: { $0.name.lowercased() == name }) {
            self = .page(index)
        } else {
            throw CommandError("There's no page \"\(name)\". Name a page by its colour (\(Self.colours)), its number from 1 to \(DotPalette.count), or \"current\" for the page Bite shows.")
        }
    }

    static var colours: String {
        DotPalette.colors.map { $0.name.lowercased() }.joined(separator: ", ")
    }

    func page(in access: some PageAccess) async throws -> Int {
        switch self {
        case .page(let page): return page
        case .shown:
            guard let page = await access.shownPage() else { throw CommandError("Bite hasn't said which page it shows: name the page by its colour.") }
            return page
        }
    }
}

extension Int {
    /// A page's colour, as it's named: "purple".
    var pageName: String {
        DotPalette.colors[self].name.lowercased()
    }
}
