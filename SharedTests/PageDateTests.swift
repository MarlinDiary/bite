import Foundation
import Testing
@testable import Bite

/// When each page last changed, which Statistics shows: here or on another device, and kept from
/// one launch to the next.
@MainActor
struct PageDateTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "BiteDateTests-\(UUID().uuidString)")

    @Test func typingChangesAPageNow() throws {
        let store = DotStore(folder: folder)
        let before = Date.now
        store.update(dot: 2, markdown: "typed\n")
        let modified = try #require(store.modified[2])
        #expect(modified >= before)
        #expect(modified <= .now)
    }

    /// A page from elsewhere changed when it did there, not when it came, and keeps that once
    /// saved, as pages untouched since the first launch keep theirs.
    @Test func aPageFromElsewhereKeepsWhenItChangedThere() throws {
        let store = DotStore(folder: folder)
        let there = Date(timeIntervalSince1970: 1_790_000_000)
        store.applyRemote(dot: 3, markdown: "from elsewhere\n", modified: there)
        #expect(store.modified[3] == there)
        store.saveNow()

        let relaunched = DotStore(folder: folder)
        let kept = try #require(relaunched.modified[3])
        #expect(abs(kept.timeIntervalSince(there)) < 0.001)
        let untouched = try #require(relaunched.modified[0])
        #expect(abs(untouched.timeIntervalSince(try #require(store.modified[0]))) < 0.001)
    }

    /// Merged with changes from here, a page changed when the newer of the two did.
    @Test func aMergedPageChangedWhenItsNewestChangeDid() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)
        #expect(PageSync.whenChanged(merged: "a\n", remote: "a\n", there: earlier, here: later) == earlier)
        #expect(PageSync.whenChanged(merged: "a\nb\n", remote: "a\n", there: earlier, here: later) == later)
        #expect(PageSync.whenChanged(merged: "a\nb\n", remote: "a\n", there: later, here: earlier) == later)
    }
}
