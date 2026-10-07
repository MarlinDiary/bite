import SwiftUI
import BiteKit
#if canImport(UIKit)
import UIKit

/// Bite in the share sheet: the pages as Bite shows them, with Cancel and Add at the dot bar's ends
/// (see `ShareModel`).
final class ShareViewController: UIViewController {
    private lazy var model = ShareModel(context: extensionContext)

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharePages(model: model).environment(model.store))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.load()
    }
}

/// Bite's pages, with Cancel where nothing is in Bite and Add where its "…" button is, each a
/// glass button as that is.
private struct SharePages: View {
    let model: ShareModel

    var body: some View {
        PagesView(leading: { _ in
            Button(role: .cancel) { model.cancel() } label: { symbol("xmark") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Cancel")
        }, trailing: { _ in
            Button { model.add() } label: { symbol("checkmark") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Add")
        }, dotColors: .asAdded(ownIsEmpty: model.ownIsEmpty))
    }

    /// Drawn as the "…" button's: the glass pads it out to the dot bar's height.
    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 30, height: 30)
    }
}
#else
import AppKit

/// Bite in the Share menu: the pages as Bite's panel shows them, with Cancel and Add at the dot
/// bar's ends (see `ShareModel`).
final class ShareViewController: NSViewController {
    private lazy var model = ShareModel(context: extensionContext)
    private var pages: PanelPages?

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let pages = PanelPages(store: model.store, size: Self.size)
        // The share sheet's window has corners of its own.
        pages.background.drawsEdge = false
        pages.addTopBar(ShareTopBar(model: model, onScreen: pages.onScreen))
        self.pages = pages
        view = pages.background
        preferredContentSize = pages.background.frame.size
    }

    /// As big as Bite's panel was last left, which Bite keeps with its copy of its settings, and
    /// no taller than the screen has room for.
    private static var size: NSSize {
        let size = PanelPages.savedSize(in: UserDefaults(suiteName: PageShelf.appGroup))
        let room = (NSScreen.main?.visibleFrame.height ?? 900) - 120
        return NSSize(width: size.width, height: max(280, min(size.height, room)))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Up, as the panel is: the page on screen takes the keys.
        pages?.isShown = { true }
        model.load()
    }
}

/// The panel's dot bar, with Cancel and Add at its ends, and each page's dot as Add would leave it.
private struct ShareTopBar: View {
    let model: ShareModel
    let onScreen: PageOnScreen

    var body: some View {
        PanelTopBar(store: model.store, onScreen: onScreen, leading: { ink in
            BarButton(symbol: "xmark", label: "Cancel", ink: ink, size: 14) { model.cancel() }
        }, trailing: { ink in
            BarButton(symbol: "checkmark", label: "Add", ink: ink) { model.add() }
        }, movesWindow: false)
            .environment(\.dotColors, .asAdded(ownIsEmpty: model.ownIsEmpty))
    }
}
#endif
