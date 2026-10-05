import Foundation
import Testing
@testable import Bite

/// The system wakes Bite in the background only for what its Info.plist names, and a task
/// registered under a name it doesn't list stops the app as it launches.
struct BackgroundSyncTests {
    @Test func theInfoPlistNamesTheBackgroundTasks() {
        let info = Bundle.main.infoDictionary ?? [:]
        let permitted = info["BGTaskSchedulerPermittedIdentifiers"] as? [String] ?? []
        #expect(permitted.contains(BackgroundSync.refreshID))
        #expect(permitted.contains(BackgroundSync.processingID))
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        #expect(Set(["fetch", "processing", "remote-notification"]).isSubset(of: Set(modes)))
    }
}
