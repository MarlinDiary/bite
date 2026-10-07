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
        /// When each page last changed, where known, for Bite's command line tool.
        var modified: [Date?]?
    }

    private var file: URL {
        folder.appending(path: "Pages.json")
    }

    /// Writes the pages, all at once, so a widget never reads some old and some new, with when
    /// each last changed, or, not given, as last written.
    public func write(_ pages: [String], modified: [Date?]? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let contents = Contents(pages: pages, modified: modified ?? readContents()?.modified)
        try JSONEncoder().encode(contents).write(to: file, options: .atomic)
    }

    /// The pages as last written, or nil before Bite has written any.
    public func read() -> [String]? {
        readContents()?.pages
    }

    /// When each page last changed, as last written: nil for a page not known, or for them all
    /// before Bite has written any.
    public func readModified() -> [Date?]? {
        readContents()?.modified
    }

    private func readContents() -> Contents? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Contents.self, from: data)
    }
}
