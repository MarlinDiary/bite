import BiteKit
import Foundation
import Observation
import UniformTypeIdentifiers
import WidgetKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Bite in the share sheet: the pages as Bite shows them, each with what's shared at its end, as it
/// would be added there, and each to be changed as in Bite. Add puts what's shared on the page on
/// screen. The pages are a copy, the one Bite keeps for its extensions, in a store of the
/// extension's own, as the extension can't reach Bite's: each page changed is left on the shelf
/// as it was and as it is now, for Bite to take in (see `PageShare`).
@MainActor @Observable
final class ShareModel {
    @ObservationIgnored let store: DotStore
    @ObservationIgnored private let shelf: PageShelf?
    /// Each page as the extension found it.
    @ObservationIgnored private let found: [String]
    /// Each page's own lines as they are now: as found, changed as they were here.
    @ObservationIgnored private var own: [String] {
        didSet {
            let isEmpty = own.map(DotStore.isBlank)
            if isEmpty != ownIsEmpty { ownIsEmpty = isEmpty }
        }
    }
    /// Each page as last put together, its own lines and what's shared at its end, or as last typed.
    @ObservationIgnored private var shown: [String]
    /// The lines shared, as they are now, in their styles and links.
    @ObservationIgnored private var lines: [[InlineRun]] = []
    @ObservationIgnored private weak var context: NSExtensionContext?
    @ObservationIgnored private let folder: URL

    /// Which pages have nothing of their own on them: the dot bar shows them so, but for the page
    /// on screen, which shows what's shared too (see `DotColors`).
    private(set) var ownIsEmpty: [Bool]

    init(context: NSExtensionContext?) {
        self.context = context
        // The choices in Bite's Settings, which Bite keeps a copy of here: the dot glowing, spelling
        // checked, the Mac's panel of glass.
        if let copy = UserDefaults(suiteName: PageShelf.appGroup) { Preferences.defaults = copy }
        shelf = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup).map(PageShelf.init(folder:))
        var pages = shelf?.read() ?? []
        if pages.count != DotPalette.count { pages = Array(repeating: "", count: DotPalette.count) }
        found = pages
        own = pages
        shown = pages
        ownIsEmpty = pages.map(DotStore.isBlank)
        folder = FileManager.default.temporaryDirectory.appending(path: "Share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (dot, page) in pages.enumerated() {
            try? page.write(to: DotStore.fileURL(for: dot, in: folder), atomically: true, encoding: .utf8)
        }
        store = DotStore(folder: folder)
        store.selection = min(max(shelf?.readLastPage() ?? 0, 0), DotPalette.count - 1)
        // Changes made here, as the editor reports them.
        store.onLocalChange = { [weak self] dot in self?.edited(dot) }
    }

    /// Reads what's shared, a web page with its title or text, and puts it at the end of every page.
    func load() {
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let title = items.lazy
            .compactMap { ($0.attributedContentText ?? $0.attributedTitle)?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                let url = Self.url(from: item)
                Task { @MainActor in self?.took(url: url, title: title) }
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                let text = item as? String ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                Task { @MainActor in self?.took(text: text ?? title ?? "") }
            }
        } else {
            took(text: title ?? "")
        }
    }

    /// What a provider gives for a web page: its address, or, as the Mac's share menu gives it, the
    /// address as data.
    private nonisolated static func url(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL: url
        case let data as Data: URL(dataRepresentation: data, relativeTo: nil)
        case let address as String: URL(string: address)
        default: nil
        }
    }

    /// A web page is a line of its title linking there; without a title, its address written out,
    /// which a page shows as a link too.
    private func took(url: URL?, title: String?) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else {
            took(text: url?.absoluteString ?? title ?? "")
            return
        }
        let address = url.absoluteString
        if let title, title != address {
            lines = [[InlineRun(title.split(whereSeparator: \.isNewline).joined(separator: " "), link: address)]]
        } else {
            lines = [[InlineRun(address)]]
        }
        place(first: true)
    }

    private func took(text: String) {
        lines = text.split(whereSeparator: \.isNewline).map { [InlineRun($0.trimmingCharacters(in: .whitespaces))] }
        place(first: true)
    }

    /// At the end of every page but `typedOn`, as if typed there: a page swiped or slid to shows it
    /// already, as it would be added there. Each page first opens at its end; after, one showing its
    /// end still does, and one scrolled up stays where it is.
    private func place(except typedOn: Int? = nil, first: Bool = false) {
        for page in found.indices where page != typedOn {
            let atEnd = first || store.pageIsAtEnd?(page) ?? true
            let markdown = PageAddition.markdown(own[page], adding: lines, asToDo: false)
            shown[page] = markdown
            store.applyRemote(dot: page, markdown: markdown)
            if atEnd { store.showEnd(dot: page) }
        }
    }

    /// `page` changed here: a change to its own lines stays its own; one to what's shared changes it
    /// on every page.
    private func edited(_ page: Int) {
        let now = store.markdown[page]
        guard now != shown[page] else { return }
        shown[page] = now
        let split = PageAddition.split(now, own: own[page], lines: lines)
        own[page] = split.own
        guard split.lines != lines else { return }
        lines = split.lines
        place(except: page)
    }

    /// Leaves for Bite the page on screen, with what's shared on it, and any other page whose own
    /// lines were changed here, as they are; puts them on the widgets' copy so they show them at
    /// once; and, on the Mac, tells Bite, running in the menu bar, to take them in now.
    func add() {
        // Typing not reported yet, which `edited` takes in.
        store.reportPendingEdits()
        let onScreen = store.selection
        if let shelf {
            var copy = shelf.read() ?? found
            for page in found.indices {
                let after = page == onScreen ? store.markdown[page] : own[page]
                guard after != found[page] else { continue }
                _ = try? shelf.leave(PageShare(page: page, before: found[page], after: after))
                if copy.indices.contains(page) { copy[page] = after }
            }
            try? shelf.write(copy)
            WidgetCenter.shared.reloadAllTimelines()
            #if os(macOS)
            DistributedNotificationCenter.default().postNotificationName(PageShelf.sharesLeft, object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
            #endif
        }
        finish()
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        finish()
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func finish() {
        try? FileManager.default.removeItem(at: folder)
    }
}
