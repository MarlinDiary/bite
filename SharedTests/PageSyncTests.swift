import CloudKit
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

    /// A new device's first-launch page, untouched, never fills a page left empty everywhere else:
    /// an iPad joining did, with its samples, on every device.
    @Test func theFirstTimeAnUntouchedSampleLeavesAnEmptyPageEmpty() {
        for dot in 1..<4 {
            #expect(PageSync.reconcile(local: SampleContent.markdown(for: dot), remote: "", agreed: nil, dot: dot) == "")
            #expect(PageSync.reconcile(local: SampleContent.markdown(for: dot), remote: "\n", agreed: nil, dot: dot) == "\n")
        }
        // First-launch pages on both, this device's stays, in its own words.
        let sample = SampleContent.markdown(for: 0)
        #expect(PageSync.reconcile(local: sample, remote: sample, agreed: nil, dot: 0) == sample)
    }

    /// A new device's empty pages don't go up: they'd only cross iCloud's on their way down. Its
    /// first-launch pages do, and an emptied page that iCloud has with something on it.
    @Test func aNewDevicesEmptyPagesDontGoUp() {
        let local = ["", "\n", SampleContent.markdown(for: 2), "", "mine\n", "theirs\n"]
        let agreed: [String?] = [nil, nil, nil, "gone\n", "mine\n", "old\n"]
        #expect(PageSync.unsent(local: local, agreed: agreed) == [2, 3, 5])
    }

    /// With the pages' zone gone from iCloud, as an App Store build finds it where development ones
    /// synced, every page goes up, unchanged ones too, or a new device would never get them; and an
    /// emptied one agreed on before. A page never written stays.
    @Test func aZoneMadeAgainGetsEveryPage() {
        let local = ["", "\n", "mine\n", "", "same\n", "changed\n"]
        let agreed: [String?] = [nil, nil, nil, "gone\n", "same\n", "old\n"]
        #expect(PageSync.resent(local: local, agreed: agreed) == [2, 3, 4, 5])
        #expect(PageSync.unsent(local: local, agreed: agreed) == [2, 3, 5])
    }

    /// Signed out of iCloud, or iCloud not allowed, a new watch stops waiting for its pages; a
    /// network that's down only holds them up.
    @Test func someFailuresMeanNothingsComing() {
        #expect(PageSync.waitsInVain(.notAuthenticated))
        #expect(PageSync.waitsInVain(.permissionFailure))
        #expect(!PageSync.waitsInVain(.networkUnavailable))
        #expect(!PageSync.waitsInVain(.requestRateLimited))
        #expect(!PageSync.waitsInVain(.serviceUnavailable))
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

    /// The first-launch pages are told apart as they came, however they're written out, and an
    /// empty page is never one.
    @Test func untouchedFirstLaunchPagesAreKnown() {
        for dot in 0..<4 {
            #expect(SampleContent.isUntouched(SampleContent.markdown(for: dot), dot: dot))
            #expect(!SampleContent.isUntouched(SampleContent.markdown(for: dot) + "one more line\n", dot: dot))
        }
        // Written out again, a list's markers as Bite writes them.
        let rewritten = MarkdownSerializer.markdown(from: MarkdownParser.parse(SampleContent.markdown(for: 3)))
        #expect(SampleContent.isUntouched(rewritten, dot: 3))
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

    /// Sync hears of another page being picked, someone using Bite, and only when it is another.
    @Test func pickingAnotherPageIsHeard() {
        let kept = UserDefaults.standard.object(forKey: "selectedDot")
        defer { UserDefaults.standard.set(kept, forKey: "selectedDot") }
        let store = store()
        var heard = 0
        store.onSelectionChange = { heard += 1 }
        let other = (store.selection + 1) % DotPalette.count
        store.selection = other
        store.selection = other
        #expect(heard == 1)
    }

    /// iCloud is asked every second while Bite is on screen, every half second while changes
    /// come in from elsewhere, every few seconds after ten quiet minutes or when it can't be
    /// reached, and every half minute off screen, on the Mac.
    @Test func howOftenICloudIsAsked() {
        let wait = { (onScreen: Bool, tookNew: Bool, failed: Bool, quiet: Duration) in
            PageSync.waitBeforeNextCheck(onScreen: onScreen, tookNew: tookNew, failed: failed, sinceActivity: quiet)
        }
        #expect(wait(true, false, false, .seconds(5)) == .seconds(1))
        #expect(wait(true, true, false, .seconds(5)) == .milliseconds(500))
        #expect(wait(true, true, false, .seconds(900)) == .milliseconds(500))
        #expect(wait(true, false, false, .seconds(900)) == .seconds(4))
        #expect(wait(true, false, true, .seconds(5)) == .seconds(4))
        #expect(wait(false, true, false, .seconds(5)) == .seconds(30))
        #expect(wait(false, false, false, .seconds(900)) == .seconds(30))
        #if os(macOS)
        #expect(PageSync.checksWhileHidden)
        #else
        #expect(!PageSync.checksWhileHidden)
        #endif
    }
}
