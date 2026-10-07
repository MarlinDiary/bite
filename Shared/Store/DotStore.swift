import Foundation
import Observation
import BiteKit

/// The Markdown behind the seven dots, kept on disk as one file per dot.
@Observable
final class DotStore {
    /// Latest Markdown for each dot. Not observed, because editors write it on every keystroke.
    @ObservationIgnored private(set) var markdown: [String]
    private(set) var isEmpty: [Bool]
    /// Bumped when a dot changes outside its editor, which makes that editor reload.
    private(set) var revisions: [Int]
    /// When each dot last changed, here or on another device. Its file keeps it as its
    /// modification date, so it lasts.
    @ObservationIgnored private(set) var modified: [Date?]
    var selection: Int {
        didSet {
            UserDefaults.standard.set(selection, forKey: Self.selectionKey)
            if selection != oldValue {
                onSelectionChange?()
                onSelectionForExtensions?(selection)
            }
        }
    }

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var unsaved: Set<Int> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Set by the editors, which report typing once it pauses: brings any change they haven't
    /// reported yet into `markdown`.
    @ObservationIgnored var reportPendingEdits: () -> Void = {}
    /// Set by the editors: empties a dot as an edit, which undo brings back.
    @ObservationIgnored var clearInEditor: ((Int) -> Void)?
    /// Set by the editors: takes in a page as another device changed it, with the caret where it
    /// was (see `EditorController.applyRemote`).
    @ObservationIgnored var applyInEditor: ((Int, String) -> Void)?
    /// Set by iCloud sync, which is told of every change made here.
    @ObservationIgnored var onLocalChange: ((Int) -> Void)?
    /// Set by iCloud sync, which is told when another page is picked: someone's using Bite.
    @ObservationIgnored var onSelectionChange: (() -> Void)?
    /// Set by the Spotlight index, which is told of the pages written to disk.
    @ObservationIgnored var onSave: ((Set<Int>) -> Void)?
    /// Set on the phone by its widgets' copy of the pages (see `WidgetShelf`), which is told when
    /// pages are written to disk.
    @ObservationIgnored var onSaveForWidgets: (() -> Void)?
    /// Set by the same, which is told when another page is picked: where the share extension opens.
    @ObservationIgnored var onSelectionForExtensions: ((Int) -> Void)?
    /// Set by the editors: shows a line on a page, and a search's words on it (see `reveal`). One
    /// asked for before the editors are there, as Bite opens at a Spotlight result, waits for them.
    @ObservationIgnored var revealInEditor: ((Int, Int?, String) -> Void)? {
        didSet {
            guard let revealInEditor, let waiting = waitingReveal else { return }
            waitingReveal = nil
            revealInEditor(waiting.dot, waiting.line, waiting.query)
        }
    }
    @ObservationIgnored private var waitingReveal: (dot: Int, line: Int?, query: String)?
    /// Set by the editors: opens a line at the end of a page and gives it the keyboard (see
    /// `startLine`). One asked for before the editors are there, as Bite launches from its icon's
    /// menu, waits for them.
    @ObservationIgnored var startLineInEditor: ((Int, Bool) -> Void)? {
        didSet {
            guard let startLineInEditor, let waiting = waitingLine else { return }
            waitingLine = nil
            startLineInEditor(waiting.dot, waiting.asToDo)
        }
    }
    @ObservationIgnored private var waitingLine: (dot: Int, asToDo: Bool)?
    /// Set by the editors: brings a page's end into view (see `showEnd`). Those asked for before the
    /// editors are there wait for them.
    @ObservationIgnored var showEndInEditor: ((Int) -> Void)? {
        didSet {
            guard let showEndInEditor else { return }
            let waiting = waitingEnds
            waitingEnds = []
            waiting.sorted().forEach(showEndInEditor)
        }
    }
    @ObservationIgnored private var waitingEnds: Set<Int> = []
    /// Set by the editors: whether a page shows its end, as the share extension keeps a page at its
    /// end as what's shared at its end changes.
    @ObservationIgnored var pageIsAtEnd: ((Int) -> Bool)?
    /// Set by the Mac's panel, which comes up on a page asked for from Siri or Shortcuts. The
    /// phone's comes up with Bite, which the system brings to the front.
    @ObservationIgnored var showInEditor: ((Int) -> Void)?

    private static let selectionKey = "selectedDot"

    static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Dots", directoryHint: .isDirectory)
    }

    init(folder: URL = DotStore.defaultFolder) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let isFirstLaunch = !FileManager.default.fileExists(atPath: Self.fileURL(for: 0, in: folder).path(percentEncoded: false))
        let markdown = (0..<DotPalette.count).map { dot in
            isFirstLaunch
                ? SampleContent.markdown(for: dot)
                : (try? String(contentsOf: Self.fileURL(for: dot, in: folder), encoding: .utf8)) ?? ""
        }
        self.markdown = markdown
        isEmpty = markdown.map(Self.isBlank)
        revisions = Array(repeating: 0, count: DotPalette.count)
        modified = (0..<DotPalette.count).map { dot in
            isFirstLaunch
                ? .now
                : try? Self.fileURL(for: dot, in: folder).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        selection = min(max(UserDefaults.standard.integer(forKey: Self.selectionKey), 0), DotPalette.count - 1)
        if isFirstLaunch {
            unsaved = Set(0..<DotPalette.count)
            saveNow()
        }
    }

    func update(dot: Int, markdown newValue: String) {
        guard markdown.indices.contains(dot), markdown[dot] != newValue else { return }
        markdown[dot] = newValue
        modified[dot] = .now
        unsaved.insert(dot)
        scheduleSave()
        onLocalChange?(dot)
    }

    /// A page as another device changed it, which iCloud brought, last changed at `date`.
    func applyRemote(dot: Int, markdown newValue: String, modified date: Date = .now) {
        guard markdown.indices.contains(dot), markdown[dot] != newValue else { return }
        markdown[dot] = newValue
        modified[dot] = date
        unsaved.insert(dot)
        scheduleSave()
        if let applyInEditor {
            applyInEditor(dot, newValue)
        } else {
            isEmpty[dot] = Self.isBlank(newValue)
            revisions[dot] += 1
        }
    }

    /// Opens a dot's page at `line`, picked in a search outside Bite, showing where `query` is on it.
    func reveal(dot: Int, line: Int?, query: String) {
        guard markdown.indices.contains(dot) else { return }
        selection = dot
        if let revealInEditor {
            revealInEditor(dot, line, query)
        } else {
            waitingReveal = (dot, line, query)
        }
    }

    /// Opens a dot's page with a line at its end to type on, the keyboard up: plain text, or a
    /// to-do, as picked from Bite's icon on the Home Screen (see `HomeScreenActions`).
    func startLine(on dot: Int, asToDo: Bool) {
        guard markdown.indices.contains(dot) else { return }
        selection = dot
        if let startLineInEditor {
            startLineInEditor(dot, asToDo)
        } else {
            waitingLine = (dot, asToDo)
        }
    }

    /// Brings the end of a dot's page into view, on screen or not, as Bite's share extension shows
    /// each page with what's shared at its end.
    func showEnd(dot: Int) {
        guard markdown.indices.contains(dot) else { return }
        if let showEndInEditor {
            showEndInEditor(dot)
        } else {
            waitingEnds.insert(dot)
        }
    }

    /// Shows a dot's page, as asked from Siri or Shortcuts.
    func open(dot: Int) {
        guard markdown.indices.contains(dot) else { return }
        selection = dot
        showInEditor?(dot)
    }

    /// Adds `text` to the end of a dot's page, from Siri or Shortcuts, as if typed there (see
    /// `PageAddition`): after any typing not reported yet, and into the editor as another device's
    /// change comes in, the caret staying where it was. Written to disk at once, as Bite may be
    /// stopped right after, run just for this. Says whether anything was added.
    @discardableResult
    func add(_ text: String, asToDo: Bool, to dot: Int) -> Bool {
        guard markdown.indices.contains(dot) else { return false }
        reportPendingEdits()
        return takeIn(PageAddition.markdown(markdown[dot], adding: text, asToDo: asToDo), on: dot)
    }

    /// Takes in a page as Bite's share extension left it (see `PageShare`), as `add` adds.
    @discardableResult
    func take(_ share: PageShare) -> Bool {
        guard markdown.indices.contains(share.page) else { return false }
        reportPendingEdits()
        return takeIn(share.applied(to: markdown[share.page]), on: share.page)
    }

    /// Ticks a to-do off, or on again, from a widget (see `PageToDos`), as `add` adds one. Says
    /// whether the page changed.
    @discardableResult
    func tick(_ tick: PageTick) -> Bool {
        guard markdown.indices.contains(tick.page) else { return false }
        reportPendingEdits()
        guard let newValue = PageToDos.markdown(markdown[tick.page], ticking: tick) else { return false }
        return takeIn(newValue, on: tick.page)
    }

    /// A change made outside the editors, from Siri or a widget: into the editor as another
    /// device's change comes in, the caret staying where it was, and written to disk at once, as
    /// Bite may be stopped right after, run just for this.
    private func takeIn(_ newValue: String, on dot: Int) -> Bool {
        guard newValue != markdown[dot] else { return false }
        markdown[dot] = newValue
        modified[dot] = .now
        unsaved.insert(dot)
        if let applyInEditor {
            applyInEditor(dot, newValue)
        } else {
            isEmpty[dot] = Self.isBlank(newValue)
            revisions[dot] += 1
        }
        saveNow()
        onLocalChange?(dot)
        return true
    }

    func update(dot: Int, isEmpty empty: Bool) {
        guard isEmpty.indices.contains(dot), isEmpty[dot] != empty else { return }
        isEmpty[dot] = empty
    }

    /// Whether Markdown reads as an empty page (nothing but empty lines), without parsing it.
    static func isBlank(_ markdown: String) -> Bool {
        markdown.unicodeScalars.enumerated().allSatisfy { index, scalar in
            (index == 0 && scalar == "\u{FEFF}") || CharacterSet.newlines.contains(scalar)
        }
    }

    /// The page's Markdown with any typing not reported yet, for copying or sharing it.
    func currentMarkdown(dot: Int) -> String {
        reportPendingEdits()
        return markdown[dot]
    }

    /// The page as plain text (see `PlainTextSerializer`), with any typing not reported yet.
    func currentPlainText(dot: Int) -> String {
        PlainTextSerializer.plainText(from: MarkdownParser.parse(currentMarkdown(dot: dot)))
    }

    func clear(dot: Int) {
        if let clearInEditor {
            clearInEditor(dot)
            saveNow()
            return
        }
        // Typing from a moment ago goes in first, so it can't come back after the page is cleared.
        reportPendingEdits()
        markdown[dot] = ""
        modified[dot] = .now
        isEmpty[dot] = true
        revisions[dot] += 1
        unsaved.insert(dot)
        saveNow()
        onLocalChange?(dot)
    }

    /// Every page as it came on first launch: the samples on the first four, the rest empty. Undo
    /// can't bring them back, so Settings asks first. It goes to iCloud as any change made here does.
    func resetAllPages() {
        // Typing from a moment ago goes in first, so it can't come back after.
        reportPendingEdits()
        for dot in markdown.indices {
            let sample = SampleContent.markdown(for: dot)
            guard markdown[dot] != sample else { continue }
            markdown[dot] = sample
            modified[dot] = .now
            isEmpty[dot] = Self.isBlank(sample)
            revisions[dot] += 1
            unsaved.insert(dot)
            onLocalChange?(dot)
        }
        saveNow()
    }

    func saveNow() {
        reportPendingEdits()
        saveTask?.cancel()
        saveTask = nil
        let saved = unsaved
        for dot in unsaved.sorted() {
            let file = Self.fileURL(for: dot, in: folder)
            try? markdown[dot].write(to: file, atomically: true, encoding: .utf8)
            // Not when it was written: a page from elsewhere changed there before it came.
            if let date = modified[dot] {
                try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path(percentEncoded: false))
            }
        }
        unsaved.removeAll()
        if !saved.isEmpty {
            onSave?(saved)
            onSaveForWidgets?()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Where a dot's page is kept in `folder`: as the share extension lays the pages out for a store
    /// of its own, too.
    static func fileURL(for dot: Int, in folder: URL) -> URL {
        folder.appending(path: "dot-\(dot + 1).md")
    }
}
