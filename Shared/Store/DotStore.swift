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
    var selection: Int {
        didSet { UserDefaults.standard.set(selection, forKey: Self.selectionKey) }
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
        selection = min(max(UserDefaults.standard.integer(forKey: Self.selectionKey), 0), DotPalette.count - 1)
        if isFirstLaunch {
            unsaved = Set(0..<DotPalette.count)
            saveNow()
        }
    }

    func update(dot: Int, markdown newValue: String) {
        guard markdown.indices.contains(dot), markdown[dot] != newValue else { return }
        markdown[dot] = newValue
        unsaved.insert(dot)
        scheduleSave()
        onLocalChange?(dot)
    }

    /// A page as another device changed it, which iCloud brought.
    func applyRemote(dot: Int, markdown newValue: String) {
        guard markdown.indices.contains(dot), markdown[dot] != newValue else { return }
        markdown[dot] = newValue
        unsaved.insert(dot)
        scheduleSave()
        if let applyInEditor {
            applyInEditor(dot, newValue)
        } else {
            isEmpty[dot] = Self.isBlank(newValue)
            revisions[dot] += 1
        }
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
        isEmpty[dot] = true
        revisions[dot] += 1
        unsaved.insert(dot)
        saveNow()
        onLocalChange?(dot)
    }

    func saveNow() {
        reportPendingEdits()
        saveTask?.cancel()
        saveTask = nil
        for dot in unsaved.sorted() {
            try? markdown[dot].write(to: Self.fileURL(for: dot, in: folder), atomically: true, encoding: .utf8)
        }
        unsaved.removeAll()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private static func fileURL(for dot: Int, in folder: URL) -> URL {
        folder.appending(path: "dot-\(dot + 1).md")
    }
}
