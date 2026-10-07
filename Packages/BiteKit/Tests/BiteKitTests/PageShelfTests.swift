import Foundation
import Testing
@testable import BiteKit

/// The copy of the pages Bite keeps for its extensions and its command line tool.
struct PageShelfTests {
    private func shelf() -> PageShelf {
        PageShelf(folder: FileManager.default.temporaryDirectory.appending(path: "PageShelfTests-\(UUID().uuidString)"))
    }

    @Test func thePagesAreKeptWithWhenTheyChanged() throws {
        let shelf = shelf()
        #expect(shelf.read() == nil)
        #expect(shelf.readModified() == nil)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try shelf.write(["One\n", ""], modified: [date, nil])
        #expect(shelf.read() == ["One\n", ""])
        #expect(shelf.readModified() == [date, nil])
        // Written without them, as a widget ticking a to-do writes the pages, they're kept.
        try shelf.write(["One\n", "Two\n"])
        #expect(shelf.read() == ["One\n", "Two\n"])
        #expect(shelf.readModified() == [date, nil])
    }

    /// The file a change is left in is gone once Bite has taken it, which the command line tool
    /// waits for.
    @Test func aChangeLeftIsGoneOnceTaken() throws {
        let shelf = shelf()
        let file = try shelf.leave(PageShare(page: 1, before: "", after: "Hi\n"))
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(shelf.takeShares() == [PageShare(page: 1, before: "", after: "Hi\n")])
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
