import SwiftUI
import UIKit
import BiteKit

/// The "…" button: settings, the page's statistics, copying it as Markdown or plain text, clearing
/// it, and sharing it: as text, or as a PDF, a picture or its Markdown. Settings and Statistics
/// come up from its window, as the window has them (see `DotMenuSheets`), so they stay up as the
/// button moves: on iPhone Duo, from the dot bar's end to the status bar's column as it folds.
struct DotMenu: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    /// Its window's, whose Settings the menu bar's Settings… asks for too, on an iPad.
    @Environment(PageWindow.self) private var window
    /// How big its glass is: the dot bar's height, or the status bar's column's on iPhone Duo.
    @Environment(\.barButtonSize) private var size

    var body: some View {
        button
            #if DEBUG
            .onAppear {
                // `-showSettings` opens Settings as the app launches, for a picture of it.
                if CommandLine.arguments.contains("-showSettings") { window.isShowingSettings = true }
                // `-showStatistics` opens Statistics as the app launches, for a picture of it.
                if CommandLine.arguments.contains("-showStatistics") { showStatistics() }
                // `-startLine` starts a line at the end of the page, the page being edited, for a
                // picture.
                if CommandLine.arguments.contains("-startLine") { store.startLine(on: dot, asToDo: false) }
            }
            #endif
    }

    /// On an iPad a bar button of the system's own, as Aa is, which the pointer lights as it does
    /// a toolbar's (see `SystemBarButton`); on a phone the system's glass button.
    @ViewBuilder
    private var button: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            SystemBarButton(symbol: "ellipsis", title: "More", edge: .trailing, tint: UIColor(DotPalette.colors[dot].color),
                            menu: { menuElements() })
                .frame(width: DotSwitcher.height, height: DotSwitcher.height)
        } else {
            let isEmpty = store.isEmpty[dot]
            Menu {
                Section {
                    Button("Settings", systemImage: "gearshape") {
                        window.isShowingSettings = true
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
                    // Neither red nor asked about: the page is cleared as an edit, which undo
                    // brings back.
                    Button("Clear Text", systemImage: "eraser") {
                        store.clear(dot: dot)
                    }
                    .disabled(isEmpty)
                }
                Section {
                    // A menu in a menu still opens when off, on its items all off: an empty page's
                    // Share is a button, off as the others are.
                    if isEmpty {
                        Button("Share", systemImage: "square.and.arrow.up") {}
                            .disabled(true)
                    } else {
                        Menu("Share", systemImage: "square.and.arrow.up") {
                            Button("Text", systemImage: "text.alignleft") {
                                ShareSheet.present(text: store.currentMarkdown(dot: dot), in: window.window)
                            }
                            Button("PDF", systemImage: "doc.richtext") { export(.pdf) }
                            Button("Image", systemImage: "photo") { export(.image) }
                            Button("Markdown", systemImage: "doc.text") { export(.markdown) }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    // The glass style pads this out by 7 points all round: to 44 points, the height
                    // of the dot bar, or the status bar's column's 48 on iPhone Duo.
                    .frame(width: size - 14, height: size - 14)
            }
            .menuOrder(.fixed)
            // The system's glass button, not a glass effect on the label: the menu grows out of it
            // and shrinks back into it. With a separate glass layer, closing the menu left a
            // second, broken rim around the button for a moment.
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    /// The same menu, for an iPad's bar button, made as it opens.
    private func menuElements() -> [UIMenuElement] {
        let isEmpty = store.isEmpty[dot]
        func action(_ title: LocalizedStringResource, _ symbol: String, isOff: Bool = false, _ handler: @escaping () -> Void) -> UIAction {
            UIAction(title: String(localized: title), image: UIImage(systemName: symbol), attributes: isOff ? .disabled : []) { _ in handler() }
        }
        let share: UIMenuElement = isEmpty
            ? action("Share", "square.and.arrow.up", isOff: true) {}
            : UIMenu(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up"), children: [
                action("Text", "text.alignleft") { ShareSheet.present(text: store.currentMarkdown(dot: dot), in: window.window) },
                action("PDF", "doc.richtext") { export(.pdf) },
                action("Image", "photo") { export(.image) },
                action("Markdown", "doc.text") { export(.markdown) },
            ])
        return [
            UIMenu(options: .displayInline, children: [
                action("Settings", "gearshape") { window.isShowingSettings = true },
                action("Statistics", "chart.bar") { showStatistics() },
            ]),
            UIMenu(options: .displayInline, children: [
                action("Copy Markdown", "doc.on.doc", isOff: isEmpty) { Clipboard.string = store.currentMarkdown(dot: dot) },
                action("Copy Plain Text", "doc.plaintext", isOff: isEmpty) { Clipboard.string = store.currentPlainText(dot: dot) },
                action("Clear Text", "eraser", isOff: isEmpty) { store.clear(dot: dot) },
            ]),
            UIMenu(options: .displayInline, children: [share]),
        ]
    }


    /// The page as a file, to the share sheet: to Files, a printer, or another app.
    private func export(_ format: PageExport.Format) {
        guard let file = PageExport.file(format, page: dot, markdown: store.currentMarkdown(dot: dot), scale: 3) else { return }
        ShareSheet.present(items: [file], in: window.window)
    }

    /// Counted as it opens, with typing from a moment ago, which changed the page just now.
    private func showStatistics() {
        let markdown = store.currentMarkdown(dot: dot)
        window.shownStatistics = ShownStatistics(statistics: PageStatistics(document: MarkdownParser.parse(markdown)),
                                                 modified: store.modified[dot])
    }
}

/// What Statistics shows for a page.
struct ShownStatistics: Identifiable {
    let id = UUID()
    let statistics: PageStatistics
    let modified: Date?
}

/// Settings and a page's statistics, from the "…" button (see `DotMenu`), up from its window: in the
/// page's colour, as they were from the button, a card in the middle of an iPad's window unless the
/// window's as narrow as a phone, where they're the phone's drawer (see `fittedSheet`); so on
/// iPhone Duo's inner display, as big as an iPad's, where the system puts its own sheets in the
/// middle too, but beside another app.
struct DotMenuSheets: ViewModifier {
    let window: PageWindow
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass

    func body(content: Content) -> some View {
        @Bindable var window = window
        let tint = DotPalette.colors[window.page].color
        content
            .sheet(isPresented: $window.isShowingSettings) {
                SettingsView()
                    .environment(\.sheetIsCard, sheetIsCard)
                    .tint(tint)
            }
            .sheet(item: $window.shownStatistics) { shown in
                StatisticsView(statistics: shown.statistics, modified: shown.modified)
                    .environment(\.sheetIsCard, sheetIsCard)
                    .tint(tint)
            }
    }

    private var sheetIsCard: Bool {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: widthClass != .compact
        case .phone: widthClass == .regular && heightClass == .regular
        default: false
        }
    }
}
