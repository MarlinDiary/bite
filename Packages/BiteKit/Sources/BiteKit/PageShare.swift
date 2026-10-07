import Foundation

/// A page as something shared to Bite from another app left it. Bite's share extension shows the
/// pages as Bite does, the shared lines at the end of one; it can't reach Bite's own files, so it
/// leaves each page it changed on the shelf, as it was and as it left it, and Bite takes them in
/// as it next runs: at once on the Mac, where Bite is in the menu bar.
public struct PageShare: Codable, Sendable, Hashable {
    /// The page, counting from 0 along the dot bar.
    public var page: Int
    /// The page as the share extension found it: the copy Bite last wrote for its extensions.
    public var before: String
    /// The page as the share extension left it.
    public var after: String

    public init(page: Int, before: String, after: String) {
        self.page = page
        self.before = before
        self.after = after
    }

    /// `current`, the page as it is now, with the share's changes made to it: line by line, as two
    /// devices' changes to a page are put together, so whatever changed in Bite since is kept too.
    public func applied(to current: String) -> String {
        TextMerge.merge(base: before, local: current, remote: after)
    }
}

extension PageShelf {
    /// Said by the share extension once it has left a page, for Bite, running, to take it in at once.
    public static let sharesLeft = Notification.Name("\(appGroup).sharesLeft")

    private var sharesFolder: URL {
        folder.appending(path: "Shares", directoryHint: .isDirectory)
    }

    /// Leaves a page for Bite, which takes it in as it next runs (see `takeShares`): each in a file
    /// of its own, so one left as Bite takes the others is neither lost nor taken twice. The file,
    /// gone once Bite has taken it.
    @discardableResult
    public func leave(_ share: PageShare, at date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: sharesFolder, withIntermediateDirectories: true)
        let name = String(format: "%017.6f", date.timeIntervalSince1970) + "-" + UUID().uuidString + ".json"
        let file = sharesFolder.appending(path: name)
        try JSONEncoder().encode(share).write(to: file, options: .atomic)
        return file
    }

    /// The pages left since Bite last took them, oldest first, which are then gone from the shelf.
    public func takeShares() -> [PageShare] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sharesFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { file in
                defer { try? FileManager.default.removeItem(at: file) }
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(PageShare.self, from: data)
            }
    }

    private var lastPageFile: URL {
        folder.appending(path: "LastPage")
    }

    /// The page Bite was last on, which the share extension opens on.
    public func writeLastPage(_ page: Int) throws {
        guard readLastPage() != page else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try String(page).write(to: lastPageFile, atomically: true, encoding: .utf8)
    }

    /// The page Bite was last on, or nil before Bite has said.
    public func readLastPage() -> Int? {
        (try? String(contentsOf: lastPageFile, encoding: .utf8)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
