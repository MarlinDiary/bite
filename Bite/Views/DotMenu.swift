import SwiftUI
import UIKit
import BiteKit

/// The "…" button: settings, copying the page as Markdown or plain text, clearing it, and
/// sharing it.
struct DotMenu: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    #if DEBUG
    /// `-showSettings` opens Settings as the app launches, for a picture of it.
    @State private var isShowingSettings = CommandLine.arguments.contains("-showSettings")
    #else
    @State private var isShowingSettings = false
    #endif

    var body: some View {
        let isEmpty = store.isEmpty[dot]
        Menu {
            Section {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
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
                Button("Share Text", systemImage: "square.and.arrow.up") {
                    ShareSheet.present(text: store.currentMarkdown(dot: dot))
                }
                .disabled(isEmpty)
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
    }
}

enum ShareSheet {
    static func present(text: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.safeAreaInsets.top + 22, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }
}
