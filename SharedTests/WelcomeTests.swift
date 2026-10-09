import Foundation
import Testing
@testable import Bite

/// Bite's welcome shows the first time it opens on a device, and only then.
@MainActor
struct WelcomeTests {
    /// The first time is when the pages are made; from then on they're read.
    @Test func onlyAStoreMakingItsPagesIsTheFirstLaunch() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BiteWelcomeTests-\(UUID().uuidString)")
        #expect(DotStore(folder: folder).isFirstLaunch)
        #expect(!DotStore(folder: folder).isFirstLaunch)
    }

    /// Not where tests run: it would come up over everything they open.
    @Test func itNeverComesUpForTests() {
        #expect(!Welcome.isDue(firstLaunch: true))
    }
}
