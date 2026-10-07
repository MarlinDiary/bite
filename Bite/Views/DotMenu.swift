import SwiftUI
import UIKit
import BiteKit

/// The "…" button: settings, the page's statistics, copying it as Markdown or plain text, clearing
/// it, and sharing it: as text, or as a PDF, a picture or its Markdown.
struct DotMenu: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    #if DEBUG
    /// `-showSettings` opens Settings as the app launches, for a picture of it.
    @State private var isShowingSettings = CommandLine.arguments.contains("-showSettings")
    #else
    @State private var isShowingSettings = false
    #endif
    @State private var shownStatistics: ShownStatistics?

    var body: some View {
        let isEmpty = store.isEmpty[dot]
        Menu {
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
                // A menu in a menu still opens when off, on its items all off: an empty page's
                // Share is a button, off as the others are.
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                // The glass style pads this out to 44 points, the height of the dot bar.
                .frame(width: 30, height: 30)
        }
        .menuOrder(.fixed)
        // The system's glass button, not a glass effect on the label: the menu grows out of it
        // and shrinks back into it. With a separate glass layer, closing the menu left a second,
        // broken rim around the button for a moment.
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(item: $shownStatistics) { shown in
            StatisticsView(statistics: shown.statistics, modified: shown.modified)
        }
        #if DEBUG
        .onAppear {
            // `-showStatistics` opens Statistics as the app launches, for a picture of it.
            if CommandLine.arguments.contains("-showStatistics") { showStatistics() }
        }
        #endif
    }

    /// The page as a file, to the share sheet: to Files, a printer, or another app.
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

enum ShareSheet {
    static func present(text: String) {
        present(items: [text])
    }

    static func present(items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.safeAreaInsets.top + 22, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }
}
