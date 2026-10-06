import Foundation

/// Every page's Markdown where Bite's widgets can read it. They can't reach Bite's own files, so
/// Bite keeps a copy in a folder it shares with them, written whenever the pages are.
public struct PageShelf: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    private struct Contents: Codable {
        var pages: [String]
    }

    private var file: URL {
        folder.appending(path: "Pages.json")
    }

    /// Writes the pages, all at once, so a widget never reads some old and some new.
    public func write(_ pages: [String]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Contents(pages: pages)).write(to: file, options: .atomic)
    }

    /// The pages as last written, or nil before Bite has written any.
    public func read() -> [String]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Contents.self, from: data).pages
    }
}
