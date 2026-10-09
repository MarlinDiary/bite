import CoreSpotlight
import SwiftUI
import UIKit
import BiteKit

/// The seven pages, a tab each, in the column visionOS's own apps keep their tabs in, down the
/// window's leading side, outside the page: each a dot in its page's colour, and, looked at, the
/// page's title beside it (user, 2026-10-09). The page is Bite's own editor, on the window's glass.
struct VisionPages: View {
    @Environment(DotStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var editors = VisionEditors()

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selection) {
            ForEach(DotPalette.colors.indices, id: \.self) { dot in
                Tab(value: dot) {
                    VisionPage(controller: editors.controllers[dot])
                } label: {
                    Label {
                        Text(title(of: dot))
                    } icon: {
                        icon(of: dot)
                    }
                }
            }
        }
        .onAppear { editors.connect(to: store) }
        // A Spotlight result, opened here.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            SpotlightIndex.open(activity, in: store)
        }
        // A link to a page, such as Siri's, opens it.
        .onOpenURL { link in
            if let page = PageTurns.page(openedBy: link) { store.open(dot: page) }
        }
    }

    /// What a page is about, for its tab: its first line with words on it, or its colour's name.
    private func title(of dot: Int) -> String {
        // Read for the page's changes, which come in as other devices' do.
        let _ = store.revisions[dot]
        return PageGlance(markdown: store.markdown[dot]).title ?? DotPalette.colors[dot].name
    }

    /// A page's dot, in its colour once it has something in it, filled in for the page on show,
    /// as the dot bar's are (see `DotSwitcher`).
    private func icon(of dot: Int) -> some View {
        Image(uiImage: VisionDot.image(ink: store.isEmpty[dot] ? DotPalette.empty : DotPalette.colors[dot],
                                       isSelected: dot == store.selection, colorScheme: colorScheme, scale: displayScale))
    }
}

/// A page's dot in the tab column, Bite's own as its dot bar has it on every other device (see
/// `DotIndicator`): shaded from the top, a fine shadow along its top edge, solid for the page on
/// show and a ring for the others, grey for an empty page. Drawn flat and pale at first, it looked
/// like another app's (user, 2026-10-09). A picture of it, in its own colours, as a tab's icon
/// is: the column takes no other view.
@MainActor
enum VisionDot {
    private static var drawn: [String: UIImage] = [:]

    static func image(ink: DotColor, isSelected: Bool, colorScheme: ColorScheme, scale: CGFloat) -> UIImage {
        let key = "\(ink.name)-\(isSelected)-\(colorScheme)-\(scale)"
        if let image = drawn[key] { return image }
        let renderer = ImageRenderer(content: DotIndicator(ink: ink, isSelected: isSelected)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        let image = (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysOriginal)
        drawn[key] = image
        return image
    }
}

/// A page in its tab: Bite's own editor on the window's glass, with Aa at the window's top leading
/// corner and "…" at its trailing one, where an iPad has them, either end of its dot bar (see
/// `FormatButton`, `DotMenu`). They're the system's own buttons, in the window's own bar, which
/// the text scrolls up under.
private struct VisionPage: View {
    let controller: EditorController
    @Environment(DotStore.self) private var store
    @State private var isShowingFormat = false
    @State private var isShowingSettings = false
    @State private var shownStatistics: ShownStatistics?

    private var dot: Int { controller.dot }

    var body: some View {
        NavigationStack {
            PageEditor(controller: controller)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { formatButton }
                    ToolbarItem(placement: .topBarTrailing) { menu }
                }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(item: $shownStatistics) { shown in
            StatisticsView(statistics: shown.statistics, modified: shown.modified)
        }
        #if DEBUG
        .onAppear {
            guard dot == store.selection else { return }
            // `-showSettings` and `-showStatistics` open them as Bite launches, `-showShareSheet`
            // shares the page as text, and `-showFormatPanel` and `-showLinkSheet` bring up the
            // format panel and Add Link, with `-startLine`, for a picture.
            let arguments = CommandLine.arguments
            if arguments.contains("-startLine") { store.startLine(on: dot, asToDo: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if arguments.contains("-showSettings") { isShowingSettings = true }
                if arguments.contains("-showStatistics") { showStatistics() }
                if arguments.contains("-showShareSheet") { ShareSheet.present(text: store.currentMarkdown(dot: dot)) }
                if arguments.contains("-showFormatPanel") { showFormatPanel() }
                if arguments.contains("-showLinkSheet") { controller.perform(.link) }
            }
        }
        #endif
    }

    /// Bite's format panel, out of Aa, as on an iPad (see `FormatPanel`).
    private var formatButton: some View {
        Button("Format", systemImage: "textformat") {
            showFormatPanel()
        }
        .popover(isPresented: $isShowingFormat) {
            FormatPanelView(panel: .shared)
                .tint(DotPalette.colors[dot].color)
        }
    }

    private func showFormatPanel() {
        // With the page not being typed in, it takes the keys first, for the styles to go on: at
        // the caret where it was.
        if FormatPanel.shared.editor !== controller { controller.focus() }
        FormatPanel.shared.refresh()
        isShowingFormat = true
    }

    /// The "…" menu, as a phone's and an iPad's: settings, the page's statistics, copying it as
    /// Markdown or plain text, clearing it, and sharing it.
    private var menu: some View {
        let isEmpty = store.isEmpty[dot]
        return Menu("More", systemImage: "ellipsis") {
            Section {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                Button("Statistics", systemImage: "chart.bar") {
                    showStatistics()
                }
            }
            Section {
                Button("Copy Markdown", systemImage: "doc.on.doc") {
                    Clipboard.string = store.currentMarkdown(dot: dot)
                }
                .disabled(isEmpty)
                Button("Copy Plain Text", systemImage: "doc.plaintext") {
                    Clipboard.string = store.currentPlainText(dot: dot)
                }
                .disabled(isEmpty)
                // Neither red nor asked about: the page is cleared as an edit, which undo brings
                // back.
                Button("Clear Text", systemImage: "eraser") {
                    store.clear(dot: dot)
                }
                .disabled(isEmpty)
            }
            Section {
                // A menu in a menu still opens when off: an empty page's Share is a button, off
                // as the others are.
                if isEmpty {
                    Button("Share", systemImage: "square.and.arrow.up") {}
                        .disabled(true)
                } else {
                    Menu("Share", systemImage: "square.and.arrow.up") {
                        Button("Text", systemImage: "text.alignleft") {
                            ShareSheet.present(text: store.currentMarkdown(dot: dot))
                        }
                        Button("PDF", systemImage: "doc.richtext") { export(.pdf) }
                        Button("Image", systemImage: "photo") { export(.image) }
                        Button("Markdown", systemImage: "doc.text") { export(.markdown) }
                    }
                }
            }
        }
        .menuOrder(.fixed)
        // Round, as Aa is: a menu's button is a capsule as wide as its title would be.
        .buttonBorderShape(.circle)
    }

    /// The page as a file, to the share sheet: to Files, or another app.
    private func export(_ format: PageExport.Format) {
        guard let file = PageExport.file(format, page: dot, markdown: store.currentMarkdown(dot: dot), scale: 3) else { return }
        ShareSheet.present(items: [file])
    }

    /// Counted as it opens, with typing from a moment ago, which changed the page just now.
    private func showStatistics() {
        let markdown = store.currentMarkdown(dot: dot)
        shownStatistics = ShownStatistics(statistics: PageStatistics(document: MarkdownParser.parse(markdown)),
                                          modified: store.modified[dot])
    }
}

/// What Statistics shows for a page.
private struct ShownStatistics: Identifiable {
    let id = UUID()
    let statistics: PageStatistics
    let modified: Date?
}

/// A page's editor, Bite's own, in its tab, on the window's own glass. The glass tinted with the
/// page's colour, and the phone's light page with the glass turned off, were tried beside it; the
/// user kept the glass (2026-10-09).
private struct PageEditor: UIViewRepresentable {
    let controller: EditorController
    @Environment(DotStore.self) private var store

    func makeUIView(context: Context) -> BiteTextView {
        // No dot bar over the page here: it's in the column beside it.
        controller.textView.isTopBarAway = true
        return controller.textView
    }

    func updateUIView(_ textView: BiteTextView, context: Context) {
        let dot = controller.dot
        guard controller.loadedRevision != store.revisions[dot] else { return }
        controller.loadedRevision = store.revisions[dot]
        controller.load(markdown: store.markdown[dot])
    }
}

/// The seven pages' editors, on the store's Markdown, reporting their own back to it, and taking
/// in what comes from other devices.
@MainActor
final class VisionEditors {
    let controllers = DotPalette.colors.indices.map { EditorController(dot: $0, accent: DotPalette.colors[$0].platformColor) }
    private var isConnected = false

    func connect(to store: DotStore) {
        guard !isConnected else { return }
        isConnected = true
        for controller in controllers {
            let dot = controller.dot
            controller.onChange = { markdown in
                store.update(dot: dot, markdown: markdown)
            }
            controller.onEmptyChange = { isEmpty in
                store.update(dot: dot, isEmpty: isEmpty)
            }
            // Links are added and changed in a card in front of the window, as on an iPad, whose
            // keys have no format bar either (see `LinkSheet`): whenever the page is being typed
            // in.
            controller.onEditLink = { [weak controller] link in
                guard let controller else { return }
                LinkSheet.shared.edit(link, on: controller)
            }
            controller.canEditLinkInBar = { true }
            controller.load(markdown: store.markdown[dot])
            controller.loadedRevision = store.revisions[dot]
        }
        store.reportPendingEdits = { [weak self] in
            self?.controllers.forEach { $0.reportPendingChange() }
        }
        store.applyInEditor = { [weak self] dot, markdown in
            self?.controllers[dot].applyRemote(markdown: markdown)
        }
        store.clearInEditor = { [weak self] dot in
            self?.controllers[dot].clear()
        }
        store.focusInEditor = { [weak self] dot in
            self?.controllers[dot].focus()
        }
        store.showEndInEditor = { [weak self] dot in
            self?.controllers[dot].showEnd()
        }
        store.pageIsAtEnd = { [weak self] dot in
            self?.controllers[dot].isAtEnd ?? true
        }
    }
}
