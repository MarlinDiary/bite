import CloudKit
import Foundation
import OSLog
import BiteKit

/// Keeps the seven pages the same on every device signed in to the same iCloud account, through
/// CloudKit. A page changed here goes up as the editor reports it, a moment after typing pauses
/// and every second while it goes on. While Bite is on screen it asks iCloud every second for
/// what other devices changed, as iCloud's pushes come late or not at all; at other times the
/// pushes bring it. Both sides' changes to a page are merged line by line (see `TextMerge`), so
/// nothing typed on either is lost.
@MainActor
final class PageSync: CKSyncEngineDelegate {
    private let store: DotStore
    /// Only once syncing starts: made without the app being allowed iCloud, as in a build for
    /// tests, it would stop the app.
    private lazy var container = CKContainer(identifier: "iCloud.com.chenyeni.bite")
    private var engine: CKSyncEngine?
    private let zoneID = CKRecordZone.ID(zoneName: "Pages", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "Page"
    private static let textField = "markdown"

    private var saved: Saved
    private let fileURL: URL
    private var sendTask: Task<Void, Never>?
    /// The engine stops the app when it's asked to send or fetch while it's asking this object
    /// something, or sending already: these keep that from happening.
    private var callsFromTheEngine = 0
    private var isSending = false
    private var sendsAgain = false
    /// While Bite is on screen, iCloud is asked every second for other devices' changes. While
    /// they're coming in, as another device is typed on, it's asked twice as often; once nothing
    /// has changed here or elsewhere for ten minutes, as with the Mac's panel left open, every
    /// few seconds.
    private static let checkInterval: Duration = .seconds(1)
    private static let busyCheckInterval: Duration = .milliseconds(500)
    private static let quietCheckInterval: Duration = .seconds(4)
    private static let quietAfter: Duration = .seconds(600)
    private var lastActivity = ContinuousClock.now
    private var checkTask: Task<Void, Never>?
    private var isChecking = false
    /// Where the last check left off: the next brings only what changed since.
    private var checkToken: CKServerChangeToken?
    /// Asked too often, or busy, iCloud says when to come back.
    private var checksPausedUntil: ContinuousClock.Instant?
    /// The text of each page on its way up. The same text in a fetch, before word that it went up,
    /// is this device's own (see `took`).
    private var sending: [Int: String] = [:]
    static let log = Logger(subsystem: "com.chenyeni.bite", category: "sync")
    /// The app's, for its delegate, which hears iCloud's pushes.
    static var shared: PageSync?
    /// Launched with `-takeICloudPages`, a device joining for the first time takes iCloud's pages
    /// in place of its own, and sends nothing until it has them.
    private var takesICloudPages = CommandLine.arguments.contains("-takeICloudPages")

    /// Kept on disk: the engine's own state, and what iCloud and this device last agreed each page
    /// said, from which both sides' changes since are worked out. A page this device hasn't heard
    /// iCloud on yet has none.
    private struct Saved: Codable {
        var engineState: CKSyncEngine.State.Serialization?
        var pages: [Page?] = Array(repeating: nil, count: DotPalette.count)

        struct Page: Codable {
            var text: String
            /// The record's system fields, which tell iCloud which version this device has.
            var systemFields: Data?
            /// When iCloud saved that version: a fetch that crossed a send can bring an older one.
            var modified: Date? = nil
        }
    }

    /// Not in the app the tests run in, which would sync the person's own pages from there, nor in
    /// one launched to take pictures of itself (`-snapshot`).
    static var runsHere: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && !CommandLine.arguments.contains("-snapshot")
    }

    init(store: DotStore, folder: URL = DotStore.defaultFolder) {
        self.store = store
        fileURL = folder.appending(path: "iCloud.json")
        saved = (try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: fileURL))) ?? Saved()
    }

    /// As the app launches: from then on it syncs while Settings says to, and stops and starts
    /// again as that's turned off and on.
    func start() {
        guard preferencesObserver == nil else { return }
        preferencesObserver = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil,
                                                                     queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPreferences() }
        }
        followPreferences()
    }

    private var preferencesObserver: (any NSObjectProtocol)?

    private func followPreferences() {
        if Preferences.syncsWithICloud, engine == nil {
            startEngine()
        } else if !Preferences.syncsWithICloud, engine != nil {
            stopEngine()
        }
    }

    private func startEngine() {
        let engine = CKSyncEngine(CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                             stateSerialization: saved.engineState, delegate: self))
        self.engine = engine
        if saved.engineState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        store.onLocalChange = { [weak self] dot in self?.pageChanged(dot) }
        Self.log.info("Started, \(self.saved.pages.compactMap { $0 }.count) pages agreed with iCloud")
        if takesICloudPages {
            Task.detached { try? await engine.fetchChanges() }
        } else {
            sendUnsentPages()
        }
        if isOnScreen { checkForChanges() }
    }

    /// Turned off in Settings, nothing more goes up or comes down. What this device and iCloud
    /// last agreed stays, so that turned on again, both sides' changes since are merged.
    private func stopEngine() {
        checkTask?.cancel()
        checkTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendsAgain = false
        checkToken = nil
        store.onLocalChange = nil
        engine = nil
        Self.log.info("Stopped")
        save()
    }

    /// Pages changed since they last went up, or that never have, go up now.
    private func sendUnsentPages() {
        let unsent = (0..<DotPalette.count).filter { saved.pages[$0]?.text != store.markdown[$0] }
        engine?.state.add(pendingRecordZoneChanges: unsent.map { .saveRecord(recordID(for: $0)) })
    }

    /// A push from iCloud, as another device changed a page: brought down at once.
    func pushArrived() async {
        Self.log.info("Push came in")
        await checkNow()
    }

    /// Set while Bite is on screen, the Mac's panel up or the app in front. Other devices'
    /// changes are then brought down at once, and every second or so after (see `checkInterval`).
    var isOnScreen = false {
        didSet {
            if isOnScreen != oldValue { checkForChanges() }
        }
    }

    private func checkForChanges() {
        checkTask?.cancel()
        checkTask = nil
        guard isOnScreen, engine != nil else { return }
        lastActivity = .now
        // Detached, as the sends are (see `scheduleSend`).
        checkTask = Task.detached { [weak self] in
            while let sync = self, !Task.isCancelled {
                let wait = await sync.checkNow()
                try? await Task.sleep(for: wait)
            }
        }
    }

    /// Asks iCloud for the pages changed since the last check, and takes them in; says how long
    /// to wait before the next. Asked to fetch, the engine asks iCloud only after a push, or as
    /// Bite comes to the front.
    @discardableResult
    private func checkNow() async -> Duration {
        if let paused = checksPausedUntil, .now < paused { return paused - .now }
        guard let engine, !isChecking else { return Self.checkInterval }
        isChecking = true
        defer { isChecking = false }
        var tookAny = false
        var tookNew = false
        var failed = false
        do {
            var moreComing = true
            while moreComing {
                let changes = try await container.privateCloudDatabase.recordZoneChanges(inZoneWith: zoneID, since: checkToken)
                // Sync turned off in Settings while iCloud was asked.
                guard self.engine === engine else { return Self.checkInterval }
                for case .success(let modification) in changes.modificationResultsByID.values
                    where !isOlderThanAgreed(modification.record) {
                    tookNew = took(modification.record, engine: engine) || tookNew
                    tookAny = true
                }
                checkToken = changes.changeToken
                moreComing = changes.moreComing
            }
        } catch let error as CKError {
            failed = true
            if error.code == .changeTokenExpired { checkToken = nil }
            if let seconds = error.retryAfterSeconds { checksPausedUntil = .now + .seconds(seconds) }
        } catch {
            failed = true
        }
        if tookAny { save() }
        if tookNew { return Self.busyCheckInterval }
        // Not signed in, offline, or with no pages up yet, it asks again no sooner than when quiet.
        return failed || .now - lastActivity > Self.quietAfter ? Self.quietCheckInterval : Self.checkInterval
    }

    private func pageChanged(_ dot: Int) {
        guard let engine else { return }
        lastActivity = .now
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: dot))])
        scheduleSend()
    }

    /// A moment after a change is reported, which the editors do as typing pauses and every
    /// second while it goes on: far sooner than the engine would on its own. One send at a time;
    /// what changes meanwhile goes right after.
    private func scheduleSend(after wait: Duration = .milliseconds(100)) {
        guard !isSending else {
            sendsAgain = true
            return
        }
        sendTask?.cancel()
        // Detached: a task made while the engine was asking this object something carried that
        // along, and the engine stopped the app when the task asked it to send.
        sendTask = Task.detached { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.sendNow()
        }
    }

    private func sendNow() async {
        guard let engine else { return }
        guard callsFromTheEngine == 0, !isSending else {
            if isSending {
                sendsAgain = true
            } else {
                scheduleSend(after: .milliseconds(300))
            }
            return
        }
        isSending = true
        // What the editors last reported: what was typed since follows once they report it, and
        // reading it back now would hold up the typing.
        try? await engine.sendChanges()
        isSending = false
        if sendsAgain {
            sendsAgain = false
            scheduleSend()
        }
    }

    // MARK: The engine

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        // One stopped in Settings may still be finishing what it was doing.
        guard syncEngine === engine else { return }
        callsFromTheEngine += 1
        defer { callsFromTheEngine -= 1 }
        switch event {
        case .stateUpdate(let update):
            saved.engineState = update.stateSerialization
        case .accountChange(let change):
            accountChanged(change.changeType, engine: syncEngine)
        case .fetchedDatabaseChanges(let changes):
            // The pages deleted from iCloud, from the account's settings: this device's go up again.
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                startOver(engine: syncEngine)
            }
        case .didFetchChanges:
            if takesICloudPages {
                takesICloudPages = false
                sendUnsentPages()
            }
        case .fetchedRecordZoneChanges(let changes):
            Self.log.info("Fetched \(changes.modifications.count) pages, \(changes.deletions.count) deleted")
            for modification in changes.modifications where !isOlderThanAgreed(modification.record) {
                took(modification.record, engine: syncEngine)
            }
            for deletion in changes.deletions {
                guard let dot = dot(for: deletion.recordID) else { continue }
                saved.pages[dot] = nil
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(deletion.recordID)])
            }
        case .sentRecordZoneChanges(let sent):
            Self.log.info("Sent \(sent.savedRecords.count) pages, \(sent.failedRecordSaves.count) failed")
            for record in sent.savedRecords {
                guard let dot = dot(for: record.recordID) else { continue }
                wentUp(record, dot: dot)
                saved.pages[dot] = Saved.Page(text: Self.text(of: record), systemFields: Self.systemFields(of: record),
                                              modified: record.modificationDate)
            }
            for failure in sent.failedRecordSaves {
                if let dot = dot(for: failure.record.recordID) { wentUp(failure.record, dot: dot) }
                failed(failure.record.recordID, failure.error, engine: syncEngine)
            }
        default:
            return
        }
        save()
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async
        -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        callsFromTheEngine += 1
        defer { callsFromTheEngine -= 1 }
        // The pages as last reported: typing since goes in the next send, once the editors report
        // it (see `sendNow`).
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        var records: [CKRecord.ID: CKRecord] = [:]
        for change in changes {
            guard case .saveRecord(let id) = change, let dot = dot(for: id) else { continue }
            records[id] = record(for: dot)
            sending[dot] = store.markdown[dot]
        }
        let batch = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { batch[$0] }
    }

    /// Word that a page's text went up, or didn't: a fetch bringing it is no longer told apart.
    private func wentUp(_ record: CKRecord, dot: Int) {
        if sending[dot] == Self.text(of: record) { sending[dot] = nil }
    }

    /// An older version of a page than the one agreed, as a fetch that crossed a send can bring.
    private func isOlderThanAgreed(_ record: CKRecord) -> Bool {
        guard let dot = dot(for: record.recordID), let agreed = saved.pages[dot]?.modified,
              let modified = record.modificationDate else { return false }
        return modified < agreed
    }

    /// The page as iCloud brought it, merged with what this device changed since they last agreed.
    /// Says whether it was new from elsewhere.
    @discardableResult
    private func took(_ record: CKRecord, engine: CKSyncEngine) -> Bool {
        guard let dot = dot(for: record.recordID) else { return false }
        let remote = Self.text(of: record)
        // This device's own text, back before word that it went up: what's here grew from it, and
        // merged with what they last agreed on it would be in twice.
        let agreed = remote == sending[dot] ? remote : saved.pages[dot]?.text
        guard remote != agreed else {
            // Nothing new from elsewhere, as when this device's own text comes back: only which
            // version iCloud has changes.
            saved.pages[dot] = Saved.Page(text: remote, systemFields: Self.systemFields(of: record), modified: record.modificationDate)
            if store.markdown[dot] != remote {
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                scheduleSend()
            }
            return false
        }
        lastActivity = .now
        store.reportPendingEdits()
        let local = store.markdown[dot]
        let merged = Self.reconcile(local: local, remote: remote, agreed: agreed, dot: dot, takingRemote: takesICloudPages)
        let age = record.modificationDate.map { Date.now.timeIntervalSince($0) } ?? 0
        Self.log.info("Page \(dot + 1): \(local.count) here, \(remote.count) in iCloud, kept \(merged.count), saved \(age, format: .fixed(precision: 1)) s ago")
        saved.pages[dot] = Saved.Page(text: remote, systemFields: Self.systemFields(of: record), modified: record.modificationDate)
        if merged != local {
            store.applyRemote(dot: dot, markdown: merged)
        }
        if merged != remote {
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            scheduleSend()
        }
        return true
    }

    /// The page to keep, given this device's and iCloud's, and what they last agreed it said.
    /// The first time, with nothing agreed, an empty page, or the first-launch one untouched, takes
    /// the other side's; two different pages are both kept whole, unless iCloud's is to be taken.
    static func reconcile(local: String, remote: String, agreed: String?, dot: Int, takingRemote: Bool = false) -> String {
        guard let agreed else {
            if takingRemote { return remote }
            if DotStore.isBlank(remote) || SampleContent.isUntouched(remote, dot: dot) { return local }
            if DotStore.isBlank(local) || SampleContent.isUntouched(local, dot: dot) { return remote }
            return TextMerge.merge(base: "", local: local, remote: remote)
        }
        return TextMerge.merge(base: agreed, local: local, remote: remote)
    }

    private func failed(_ id: CKRecord.ID, _ error: CKError, engine: CKSyncEngine) {
        guard let dot = dot(for: id) else { return }
        Self.log.error("Page \(dot + 1) didn't go up: \(error.code.rawValue) \(error.localizedDescription)")
        switch error.code {
        case .serverRecordChanged:
            // Changed on another device since this one last heard: merged with that, and sent again.
            if let server = error.serverRecord {
                took(server, engine: engine)
            } else {
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }
        case .zoneNotFound:
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        case .unknownItem:
            // Gone from iCloud: it goes up afresh.
            saved.pages[dot]?.systemFields = nil
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        default:
            // The engine tries again itself after errors that pass, such as no network.
            break
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType, engine: CKSyncEngine) {
        Self.log.info("iCloud account changed: \(String(describing: change))")
        switch change {
        case .signIn, .switchAccounts:
            // Another account's pages: this device's are merged with them, as the first time.
            startOver(engine: engine)
        case .signOut:
            saved.pages = Array(repeating: nil, count: DotPalette.count)
        @unknown default:
            break
        }
    }

    private func startOver(engine: CKSyncEngine) {
        saved.pages = Array(repeating: nil, count: DotPalette.count)
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        engine.state.add(pendingRecordZoneChanges: (0..<DotPalette.count).map { .saveRecord(recordID(for: $0)) })
    }

    // MARK: Records

    private func record(for dot: Int) -> CKRecord {
        let record = saved.pages[dot]?.systemFields.flatMap(Self.record(withSystemFields:))
            ?? CKRecord(recordType: Self.recordType, recordID: recordID(for: dot))
        record[Self.textField] = store.markdown[dot] as NSString
        return record
    }

    private func recordID(for dot: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "dot-\(dot + 1)", zoneID: zoneID)
    }

    private func dot(for id: CKRecord.ID) -> Int? {
        guard id.zoneID == zoneID, id.recordName.hasPrefix("dot-"), let number = Int(id.recordName.dropFirst(4)),
              (1...DotPalette.count).contains(number) else { return nil }
        return number - 1
    }

    private static func text(of record: CKRecord) -> String {
        record[textField] as? String ?? ""
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func record(withSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private func save() {
        try? JSONEncoder().encode(saved).write(to: fileURL, options: .atomic)
    }
}
