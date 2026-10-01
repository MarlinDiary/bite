import Foundation
import Testing
import BiteKit
@testable import Bite

/// What iCloud sync keeps of a page changed on this device and on another.
@MainActor
struct PageSyncTests {
    /// Both devices' changes since they last agreed on the page go in.
    @Test func changesOnBothDevicesBothGoIn() {
        let page = PageSync.reconcile(local: "a\nB\nc\n", remote: "a\nb\nC\n", agreed: "a\nb\nc\n", dot: 4)
        #expect(page == "a\nB\nC\n")
    }

    /// The first time, an empty page, or the first-launch one untouched, takes the other side's.
    @Test func theFirstTimeAnUntouchedPageTakesTheOther() {
        let mine = "- [ ] call the plumber\n"
        #expect(PageSync.reconcile(local: "", remote: mine, agreed: nil, dot: 4) == mine)
        #expect(PageSync.reconcile(local: mine, remote: "\n", agreed: nil, dot: 4) == mine)
        #expect(PageSync.reconcile(local: SampleContent.markdown(for: 1), remote: mine, agreed: nil, dot: 1) == mine)
        #expect(PageSync.reconcile(local: mine, remote: SampleContent.markdown(for: 1), agreed: nil, dot: 1) == mine)
    }

    /// Two different pages, the first time, are both kept whole, this device's first.
    @Test func theFirstTimeTwoDifferentPagesAreBothKept() {
        #expect(PageSync.reconcile(local: "mine\n", remote: "theirs\n", agreed: nil, dot: 5) == "mine\ntheirs\n")
    }

    /// A device joining with `-takeICloudPages` takes iCloud's pages the first time, its own
    /// set aside, and merges as any other afterwards.
    @Test func takingICloudsPagesIsOnlyTheFirstTime() {
        #expect(PageSync.reconcile(local: "mine\n", remote: "theirs\n", agreed: nil, dot: 5, takingRemote: true) == "theirs\n")
        #expect(PageSync.reconcile(local: "a\nB\n", remote: "a\nb\n", agreed: "a\nb\n", dot: 5, takingRemote: true) == "a\nB\n")
    }

    /// The first-launch pages are told apart however they're written, on a phone or on a Mac.
    @Test func untouchedFirstLaunchPagesAreKnown() {
        for dot in 0..<4 {
            #expect(SampleContent.isUntouched(SampleContent.markdown(for: dot), dot: dot))
            #expect(!SampleContent.isUntouched(SampleContent.markdown(for: dot) + "one more line\n", dot: dot))
        }
        // The other device's wording, a tap rather than a click.
        let phone = SampleContent.markdown(for: 0).replacingOccurrences(of: "Click a dot up top, or press ⌘1 to ⌘7, to switch.",
                                                                     with: "Swipe, or tap a dot up top to switch.")
            .replacingOccurrences(of: "Click a checkbox", with: "Tap a checkbox")
        let mac = SampleContent.markdown(for: 0).replacingOccurrences(of: "Swipe, or tap a dot up top to switch.",
                                                                   with: "Click a dot up top, or press ⌘1 to ⌘7, to switch.")
            .replacingOccurrences(of: "Tap a checkbox", with: "Click a checkbox")
        #expect(SampleContent.isUntouched(phone, dot: 0))
        #expect(SampleContent.isUntouched(mac, dot: 0))
        #expect(!SampleContent.isUntouched("", dot: 5))
    }

    private func store() -> DotStore {
        DotStore(folder: FileManager.default.temporaryDirectory.appending(path: "BiteSyncTests-\(UUID().uuidString)"))
    }

    /// Sync hears of changes made here, and only of those.
    @Test func onlyChangesMadeHereGoOut() {
        let store = store()
        var changed: [Int] = []
        store.onLocalChange = { changed.append($0) }
        store.update(dot: 2, markdown: "typed here\n")
        store.applyRemote(dot: 3, markdown: "from elsewhere\n")
        #expect(changed == [2])
        #expect(store.markdown[3] == "from elsewhere\n")
    }

    /// A page from elsewhere goes to its editor, which keeps the caret, rather than reloading it.
    @Test func aPageFromElsewhereGoesToItsEditor() {
        let store = store()
        var applied: [(Int, String)] = []
        store.applyInEditor = { applied.append(($0, $1)) }
        let revisions = store.revisions
        store.applyRemote(dot: 1, markdown: "from elsewhere\n")
        #expect(applied.map(\.0) == [1])
        #expect(store.revisions == revisions)
        store.applyInEditor = nil
        store.applyRemote(dot: 1, markdown: "again\n")
        #expect(store.revisions[1] == revisions[1] + 1)
    }
}
