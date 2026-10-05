import BackgroundTasks
import Foundation
import OSLog

/// Lets Bite sync while it's off screen, at times the system picks: every so often, as often as
/// the system allows for how Bite is used (asked for no more than every 15 minutes), and now and
/// then with the phone charging and on a network, as overnight. iCloud's pushes wake it too (see
/// `AppDelegate`). None of these come once Bite has been swiped away in the app switcher, until
/// it's opened again, and the refresh not in Low Power Mode or with Background App Refresh off.
enum BackgroundSync {
    static let refreshID = "com.chenyeni.bite.refresh"
    static let processingID = "com.chenyeni.bite.processing"

    /// As Bite launches, before it finishes launching: the system asks for these by name.
    static func register() {
        for id in [refreshID, processingID] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
                MainActor.assumeIsolated { run(task) }
            }
        }
    }

    /// As Bite leaves the screen, and after each run: the next chances. Asked again, the system
    /// replaces what was asked before.
    static func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = .now + 15 * 60
        submit(refresh)
        let processing = BGProcessingTaskRequest(identifier: processingID)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = true
        processing.earliestBeginDate = .now + 60 * 60
        submit(processing)
    }

    private static func submit(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            PageSync.log.error("Couldn't ask for \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func run(_ task: BGTask) {
        schedule()
        let completion = Completion(task)
        let reason = task.identifier == refreshID ? "refresh" : "processing"
        let work = Task {
            await PageSync.shared?.syncInBackground(reason)
            completion.finish(success: !Task.isCancelled)
        }
        // Out of time: what's under way stops, and the system hears so.
        task.expirationHandler = {
            DispatchQueue.main.async {
                work.cancel()
                completion.finish(success: false)
            }
        }
    }

    /// Tells the system a task is done, once.
    private final class Completion {
        private let task: BGTask
        private var isDone = false

        init(_ task: BGTask) {
            self.task = task
        }

        func finish(success: Bool) {
            guard !isDone else { return }
            isDone = true
            task.setTaskCompleted(success: success)
        }
    }
}
