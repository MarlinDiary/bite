import SwiftUI
import UIKit
import BiteKit

/// One of Bite's windows: the page it shows, its pager, and what the menu bar does in it. An iPad
/// can have several open, each on a page of its own (user, 2026-10-09). Two on the same page show
/// it alike, each taking in the other's typing as it's reported (see `PageWindows`).
@MainActor @Observable
final class PageWindow {
    /// The page on screen, picked in this window alone.
    var page: Int {
        didSet {
            if page != oldValue { PageWindows.shared.pageDidChange(in: self) }
        }
    }
    /// Asked for by the menu bar's Settings…, which this window's "…" button shows (see
    /// `DotMenu`).
    var isShowingSettings = false
    @ObservationIgnored weak var pager: DotPagerCoordinator?

    init(page: Int) {
        self.page = page
    }

    /// The window on screen, once the pager's in it.
    var window: UIWindow? {
        pager?.container.window
    }

    /// The page being typed in here, if one is.
    var editor: EditorController? {
        pager?.controllers.first { $0.textView.isFirstResponder }
    }

    /// The page on screen's editor.
    var pageEditor: EditorController? {
        guard let pager, pager.controllers.indices.contains(page) else { return nil }
        return pager.controllers[page]
    }

    // MARK: Find, from the menu bar

    /// Finds on the page on screen, typed in or not, in the system's find bar, as Notes does.
    func find() {
        pageEditor?.textView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    /// The next match, or the find bar if it isn't up.
    func findNext() {
        guard let find = pageEditor?.textView.findInteraction else { return }
        if find.isFindNavigatorVisible {
            find.findNext()
        } else {
            find.presentFindNavigator(showingReplace: false)
        }
    }

    /// The match before, or the find bar if it isn't up.
    func findPrevious() {
        guard let find = pageEditor?.textView.findInteraction else { return }
        if find.isFindNavigatorVisible {
            find.findPrevious()
        } else {
            find.presentFindNavigator(showingReplace: false)
        }
    }
}

/// Bite's windows. The one in front is where a page opened from elsewhere goes: from Spotlight, a
/// widget, Siri or Bite's icon; and the page it shows is the page Bite is on, as the widgets and
/// the share extension know it. The store's hooks into the pages' editors are answered here, for
/// every window at once or for the one in front.
@MainActor
final class PageWindows {
    static let shared = PageWindows()

    private struct Entry {
        weak var window: PageWindow?
    }

    private var entries: [Entry] = []
    private weak var current: PageWindow?
    private weak var store: DotStore?

    /// The window in use is the one last touched or typed in, brought to the front, or opened in
    /// from elsewhere. UIKit's own key windows say nothing of it: each window is its scene's key
    /// window.
    private init() {
        NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            let scene = note.object as? UIWindowScene
            MainActor.assumeIsolated {
                guard let self, let scene, let window = self.window(in: scene) else { return }
                self.makeCurrent(window)
            }
        }
    }

    /// The windows open, oldest first.
    var all: [PageWindow] {
        entries.compactMap(\.window)
    }

    /// The window in front: the one last in use.
    var front: PageWindow? {
        current ?? all.last
    }

    /// The window showing `scene`, if Bite's has it.
    func window(in scene: UIWindowScene) -> PageWindow? {
        all.first { $0.window?.windowScene === scene }
    }

    /// A window's pager, as it's made. The first one hands the store the hooks into the pages'
    /// editors, which go to every window from then on.
    func attach(_ pager: DotPagerCoordinator, to window: PageWindow, store: DotStore) {
        window.pager = pager
        entries.removeAll { $0.window == nil || $0.window === window }
        entries.append(Entry(window: window))
        // Bite has the one store; a test, one of its own.
        if self.store !== store {
            self.store = store
            hook(store)
        }
        if current == nil { makeCurrent(window) }
    }

    /// Opens another window, on the page Bite's on, the one `window` shows: from the menu bar's
    /// New Window. Beside `window`, as the system places a window asked for from another.
    func openWindow(from window: PageWindow?) {
        if let window { makeCurrent(window) }
        var request = UISceneSessionActivationRequest(role: .windowApplication)
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = front?.window?.windowScene
        request.options = options
        UIApplication.shared.activateSceneSession(for: request)
    }

    /// A window's pages touched, or typed in: it's the one in use.
    func pagerWasUsed(_ pager: DotPagerCoordinator) {
        guard let window = all.first(where: { $0.pager === pager }), window !== current else { return }
        makeCurrent(window)
    }

    /// A window's pages on screen, as it opens: in front if it opened there, as a new window does.
    func pagerAppeared(_ pager: DotPagerCoordinator) {
        guard let window = all.first(where: { $0.pager === pager }) else { return }
        if pager.container.window?.windowScene?.activationState == .foregroundActive {
            makeCurrent(window)
        } else {
            updateTitle(of: window)
        }
    }

    /// The window in front from now on, as it's made key, or as something's opened in it: the page
    /// it shows is the one Bite's on, and the page typed in there is the one the menu bar and the
    /// format panel act on.
    func makeCurrent(_ window: PageWindow) {
        // Typing in the window let go of, not reported yet, goes to the others now: before
        // they're typed in, which would leave it out.
        if let previous = current, previous !== window {
            previous.pager?.controllers.forEach { $0.reportPendingChange() }
        }
        current = window
        if store?.selection != window.page { store?.selection = window.page }
        if let editor = window.editor, FormatBar.shared.editor !== editor {
            FormatBar.shared.editor = editor
            FormatBar.shared.refresh()
        }
        updateTitle(of: window)
    }

    func pageDidChange(in window: PageWindow) {
        if window === front, store?.selection != window.page { store?.selection = window.page }
        updateTitle(of: window)
    }

    /// A page's typing as its editor reports it, which changed the store: the other windows'
    /// editors for the page take it in as another device's change comes, the caret staying where
    /// it was.
    func pageChanged(_ dot: Int, markdown: String, in pager: DotPagerCoordinator) {
        for window in all where window.pager !== pager {
            window.pager?.controllers[dot].applyRemote(markdown: markdown)
        }
        updateTitles(showing: dot)
    }

    private func hook(_ store: DotStore) {
        store.reportPendingEdits = { [weak self] in
            self?.all.forEach { $0.pager?.controllers.forEach { $0.reportPendingChange() } }
        }
        store.applyInEditor = { [weak self] dot, markdown in
            guard let self else { return }
            for window in self.all {
                window.pager?.controllers[dot].applyRemote(markdown: markdown)
                window.pager?.prewarmLinks(on: dot, again: true)
            }
            self.updateTitles(showing: dot)
        }
        store.clearInEditor = { [weak self] dot in
            self?.front?.pager?.controllers[dot].clear()
        }
        store.revealInEditor = { [weak self] dot, line, query in
            guard let window = self?.front else { return }
            window.page = dot
            window.pager?.reveal(dot: dot, line: line, query: query)
        }
        store.focusInEditor = { [weak self] dot in
            self?.front?.pager?.controllers[dot].focus()
        }
        store.startLineInEditor = { [weak self] dot, asToDo in
            guard let window = self?.front else { return }
            window.page = dot
            window.pager?.startLine(on: dot, asToDo: asToDo)
        }
        store.showEndInEditor = { [weak self] dot in
            self?.front?.pager?.controllers[dot].showEnd()
        }
        store.pageIsAtEnd = { [weak self] dot in
            self?.front?.pager?.controllers[dot].isAtEnd ?? true
        }
        // A page opened from Siri, Shortcuts or a widget.
        store.showInEditor = { [weak self] dot in
            self?.front?.page = dot
        }
    }

    /// Each window's name in the system's list of them: the page's heading, or its dot's name, as
    /// a page sent or shared is named.
    private func updateTitle(of window: PageWindow) {
        guard let store, let scene = window.window?.windowScene, store.markdown.indices.contains(window.page) else { return }
        let page = window.page
        let title = PageGlance(markdown: store.markdown[page]).title ?? "\(DotPalette.colors[page].name) Dot"
        if scene.title != title { scene.title = title }
    }

    private func updateTitles(showing dot: Int) {
        all.filter { $0.page == dot }.forEach(updateTitle)
    }
}
