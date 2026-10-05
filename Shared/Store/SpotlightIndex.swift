import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers
import BiteKit

/// Puts what's on the pages in Spotlight, on this device, so it can be found from outside Bite:
/// an item to a line, titled by the line, under its page's first line and its dot's colour.
/// Spotlight shows an app's item only when what's searched for is in its title, so a page as one
/// item could be found only by its first line. As a page is saved, the lines that changed go in
/// and come out; as Bite starts, whatever changed since; none while Settings says not to. A
/// result picked opens its page at the line (see `open`).
final class SpotlightIndex: NSObject, CSSearchableIndexDelegate {
    nonisolated static let log = Logger(subsystem: "com.chenyeni.bite", category: "spotlight")

    private let store: DotStore
    private let index: PageSearchIndex
    private let defaults: UserDefaults
    private var isOn = Preferences.showsInSpotlight
    /// What's in Spotlight for each page, as put in.
    private var indexed: [Int: Indexed] = [:]
    /// Named afresh each time everything goes in, and kept both with what's in Spotlight and in
    /// the defaults with `indexed`: Spotlight can lose an app's items, as when its index is built
    /// again, and what's noted here is only true while the two names match.
    private var generation = ""
    /// Until Spotlight says what it has, as Bite starts, or while everything is going in or
    /// coming out, a page saved isn't put in on its own.
    private var isReady = false
    private var isReplacing = false
    private var preferences: NSObjectProtocol?

    private struct Indexed: Codable {
        /// The page's first line, which every line's item shows.
        var firstLine: String
        var identifiers: Set<String>
    }

    private struct Saved: Codable {
        var version: Int
        /// Where the app was, which the items' pictures are read from.
        var app: String
        var generation: String
        var pages: [Int: Indexed]
    }

    private static let savedKey = "spotlight"
    /// Raised as the items change how they look, which puts them all in again as Bite next starts.
    private static let version = 4

    init(store: DotStore, index: PageSearchIndex = CSSearchableIndex(name: "Pages"), defaults: UserDefaults = .standard) {
        self.store = store
        self.index = index
        self.defaults = defaults
    }

    /// Not in the app the tests run in, nor in one launched to take pictures of itself, which
    /// keep pages other than the person's (see `PageSync.runsHere`).
    static var runsHere: Bool {
        PageSync.runsHere && CSSearchableIndex.isIndexingAvailable()
    }

    func start() {
        (index as? CSSearchableIndex)?.indexDelegate = self
        store.onSave = { [weak self] dots in
            guard let self, isOn, isReady, !isReplacing else { return }
            update(dots.sorted())
        }
        preferences = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
        guard isOn else {
            isReady = true
            takeAllOut()
            return
        }
        index.fetchState { [weak self] state in
            onMain { self?.started(spotlightHas: state) }
        }
    }

    /// What's noted here goes on if Spotlight has what was last put in, and everything goes in
    /// afresh otherwise. Turned off meanwhile, everything comes out.
    private func started(spotlightHas state: Data?) {
        isReady = true
        guard isOn else {
            takeAllOut()
            return
        }
        let saved = defaults.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        if let saved, saved.version == Self.version, saved.app == Bundle.main.bundlePath, let state, state == Data(saved.generation.utf8) {
            generation = saved.generation
            indexed = saved.pages
            update(Array(store.markdown.indices))
        } else {
            putAllIn()
        }
    }

    private func preferencesChanged() {
        guard Preferences.showsInSpotlight != isOn else { return }
        isOn = Preferences.showsInSpotlight
        guard isReady else { return }
        if isOn {
            putAllIn()
        } else {
            takeAllOut()
        }
    }

    /// Every line goes in, and whatever else of Bite's Spotlight has comes out, together, once
    /// Spotlight says what it has. Taken out all at once, or by page, items went only later, and
    /// took the lines put in meanwhile with them; taken out one by one, they go in order.
    private func putAllIn() {
        replaceAll(.putAllIn)
    }

    private func takeAllOut() {
        replaceAll(.takeAllOut)
    }

    private nonisolated enum Replacement {
        case putAllIn, takeAllOut
    }

    private var replacing: UUID?

    /// Asks Spotlight for everything of Bite's it has, then replaces it, unless it's been asked
    /// for again meanwhile.
    private func replaceAll(_ replacement: Replacement) {
        isReplacing = true
        let request = UUID()
        replacing = request
        index.fetchIdentifiers { [weak self] present in
            onMain { self?.replace(Set(present), request: request, with: replacement) }
        }
    }

    private func replace(_ present: Set<String>, request: UUID, with replacement: Replacement) {
        guard replacing == request else { return }
        isReplacing = false
        indexed = [:]
        index.beginBatch()
        switch replacement {
        case .putAllIn:
            generation = UUID().uuidString
            putIn(Array(store.markdown.indices))
            let rest = present.subtracting(indexed.values.flatMap(\.identifiers))
            if !rest.isEmpty { index.delete(identifiers: rest.sorted()) }
            endBatch()
        case .takeAllOut:
            generation = ""
            defaults.removeObject(forKey: Self.savedKey)
            if !present.isEmpty { index.delete(identifiers: present.sorted()) }
            index.endBatch(state: Data()) { _ in }
        }
    }

    private func update(_ dots: [Int]) {
        index.beginBatch()
        putIn(dots)
        endBatch()
    }

    /// Puts each page's new lines in and takes out the ones that have gone. A new first line,
    /// which every item shows, puts the whole page in again; the first line's own item, which
    /// shows what follows it, goes in each time. What comes out is never what goes in.
    private func putIn(_ dots: [Int]) {
        for dot in dots {
            let lines = Self.lines(for: dot, markdown: store.markdown[dot])
            let firstLine = lines.first?.text ?? ""
            let before = indexed[dot]
            let wanted = lines.enumerated().filter { position, line in
                position == 0 || before?.firstLine != firstLine || before?.identifiers.contains(line.identifier) != true
            }.map(\.element)
            let identifiers = Set(lines.map(\.identifier))
            let gone = (before?.identifiers ?? []).subtracting(identifiers)
            if !wanted.isEmpty {
                index.index(wanted.map { Self.item(for: $0, in: lines, dot: dot, modified: store.modified[dot]) })
            }
            if !gone.isEmpty {
                index.delete(identifiers: gone.sorted())
            }
            indexed[dot] = lines.isEmpty ? nil : Indexed(firstLine: firstLine, identifiers: identifiers)
        }
    }

    /// Ends the batch, keeping the generation with it, and notes what's in once it's kept.
    private func endBatch() {
        let saved = Saved(version: Self.version, app: Bundle.main.bundlePath, generation: generation, pages: indexed)
        index.endBatch(state: Data(generation.utf8)) { [weak self] kept in
            onMain { self?.batchEnded(saved, kept: kept) }
        }
    }

    /// Noted once Spotlight has kept it; not kept, it's all put in afresh as Bite next starts.
    private func batchEnded(_ saved: Saved, kept: Bool) {
        guard saved.generation == generation else { return }
        if kept {
            defaults.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
        } else {
            defaults.removeObject(forKey: Self.savedKey)
        }
    }

    // MARK: Asked by Spotlight

    /// Spotlight lost what it had, or some of it: everything goes in again.
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex,
                                     reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        putAllInAgain(then: Acknowledgement(acknowledgementHandler))
    }

    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String],
                                     acknowledgementHandler: @escaping () -> Void) {
        putAllInAgain(then: Acknowledgement(acknowledgementHandler))
    }

    private nonisolated func putAllInAgain(then acknowledgement: Acknowledgement) {
        Task { @MainActor in
            if isOn, isReady { putAllIn() }
            acknowledgement.call()
        }
    }

    /// Spotlight's word that it's done, called once everything is on its way in, on the main actor.
    private nonisolated struct Acknowledgement: @unchecked Sendable {
        let call: () -> Void

        init(_ call: @escaping () -> Void) {
            self.call = call
        }
    }

    // MARK: Opening a result

    /// Opens the page a Spotlight result picked is on, at its line, showing what was searched for.
    /// Returns whether the activity was one.
    @discardableResult
    static func open(_ activity: NSUserActivity, in store: DotStore) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let dot = dot(forIdentifier: identifier) else { return false }
        // The line where it is now: lines above it may have come or gone since it was put in.
        let line = lines(for: dot, markdown: store.markdown[dot]).first { $0.identifier == identifier }?.position
        log.info("Opening a result on dot \(dot), line \(line.map(String.init) ?? "gone")")
        store.reveal(dot: dot, line: line, query: activity.userInfo?[CSSearchQueryString] as? String ?? "")
        return true
    }

    // MARK: Items

    /// A line with something on it, as it reads: no bullet, box or Markdown. Its identifier is its
    /// page's, as its file and its iCloud record are named, its text's, and how many lines on the
    /// page above it read the same: the same as long as the line is there, wherever it moves.
    struct Line: Equatable {
        let identifier: String
        let text: String
        /// Where it is on the page, counting every line.
        let position: Int
    }

    static func lines(for dot: Int, markdown: String) -> [Line] {
        let blocks = MarkdownParser.parse(markdown).blocks
        var seen: [String: Int] = [:]
        var lines: [Line] = []
        for (position, block) in blocks.enumerated() {
            let text = block.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let key = fingerprint(text)
            let repeats = seen[key, default: 0]
            seen[key] = repeats + 1
            lines.append(Line(identifier: "\(pageName(dot)):\(key):\(repeats)", text: text, position: position))
        }
        return lines
    }

    static func dot(forIdentifier identifier: String) -> Int? {
        let page = identifier.prefix { $0 != ":" }
        guard page.hasPrefix("dot-"), let number = Int(page.dropFirst(4)), (1...DotPalette.count).contains(number) else { return nil }
        return number - 1
    }

    private static func pageName(_ dot: Int) -> String {
        "dot-\(dot + 1)"
    }

    /// FNV-1a over the text's UTF-8, in hex: the same on every launch and device, as Swift's own
    /// hashes aren't.
    private static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// A line's item: the line, and under it its page's first line, or for the first line, what
    /// follows it.
    static func item(for line: Line, in lines: [Line], dot: Int, modified: Date?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
        attributes.title = String(line.text.prefix(1000))
        attributes.textContent = line.text
        if line == lines.first {
            attributes.contentDescription = String(lines.dropFirst().map(\.text).joined(separator: "  ").prefix(300))
        } else {
            attributes.contentDescription = lines.first.map { String($0.text.prefix(200)) }
        }
        attributes.contentModificationDate = modified
        // Where the picture is in the app, rather than the picture itself in every item.
        attributes.thumbnailURL = thumbnailURL(for: dot)
        let item = CSSearchableItem(uniqueIdentifier: line.identifier, domainIdentifier: pageName(dot), attributeSet: attributes)
        // Items go after a month otherwise, and a line may stay as it is for longer.
        item.expirationDate = .distantFuture
        return item
    }

    /// Each dot's ring as the app icon in its colour has it, as on the Home Screen. Spotlight
    /// reads it from the app, which moves as it's updated: everything goes in again then (see
    /// `Saved.app`).
    static func thumbnailURL(for dot: Int) -> URL? {
        Bundle.main.url(forResource: "SpotlightRing-\(DotPalette.colors[dot].name)", withExtension: "png")
    }
}

/// Where the items go: Spotlight's index on this device, or the tests' own. Changes go in
/// batches, each kept with a little state of the app's own, which comes back as it was only while
/// Spotlight has what was put in.
protocol PageSearchIndex {
    func beginBatch()
    func index(_ items: [CSSearchableItem])
    func delete(identifiers: [String])
    /// Ends the batch, keeping `state` with it, and says whether it was kept.
    func endBatch(state: Data, then done: @escaping @Sendable (Bool) -> Void)
    func fetchState(then done: @escaping @Sendable (Data?) -> Void)
    /// Everything of Bite's Spotlight has, by identifier.
    func fetchIdentifiers(then done: @escaping @Sendable ([String]) -> Void)
}

extension CSSearchableIndex: PageSearchIndex {
    func index(_ items: [CSSearchableItem]) {
        indexSearchableItems(items, completionHandler: nil)
    }

    func delete(identifiers: [String]) {
        deleteSearchableItems(withIdentifiers: identifiers, completionHandler: nil)
    }

    func endBatch(state: Data, then done: @escaping @Sendable (Bool) -> Void) {
        endBatch(withClientState: state) { @Sendable error in
            if let error { SpotlightIndex.log.error("Couldn't put lines in Spotlight: \(error.localizedDescription, privacy: .public)") }
            done(error == nil)
        }
    }

    func fetchState(then done: @escaping @Sendable (Data?) -> Void) {
        fetchLastClientState { @Sendable state, error in
            if let error { SpotlightIndex.log.error("Couldn't ask Spotlight what it has: \(error.localizedDescription, privacy: .public)") }
            done(state)
        }
    }

    func fetchIdentifiers(then done: @escaping @Sendable ([String]) -> Void) {
        let found = FoundIdentifiers()
        let query = CSSearchQuery(queryString: "title == \"*\"", queryContext: CSSearchQueryContext())
        query.foundItemsHandler = { @Sendable items in
            found.add(items.map(\.uniqueIdentifier))
        }
        query.completionHandler = { @Sendable error in
            if let error { SpotlightIndex.log.error("Couldn't ask Spotlight what it has: \(error.localizedDescription, privacy: .public)") }
            done(found.all)
        }
        query.start()
    }
}

/// The identifiers a query finds, as they come, from a queue of its own.
private nonisolated final class FoundIdentifiers: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String] = []

    func add(_ more: [String]) {
        lock.withLock { identifiers += more }
    }

    var all: [String] {
        lock.withLock { identifiers }
    }
}

/// Runs `work` on the main actor: at once if already there, as the tests' index answers, and
/// soon otherwise, as Spotlight does, from a queue of its own.
private nonisolated func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(work)
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
