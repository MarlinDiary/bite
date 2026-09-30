import SwiftUI
import UIKit
import BiteKit

/// The "…" button: copy as Markdown, share, clear, and the app icon's colour.
struct DotMenu: View {
    let dot: Int
    @Environment(DotStore.self) private var store
    @State private var isConfirmingClear = false

    var body: some View {
        Menu {
            Section {
                Button("Copy as Markdown", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = store.currentMarkdown(dot: dot)
                }
                Button("Share…", systemImage: "square.and.arrow.up") {
                    ShareSheet.present(text: store.currentMarkdown(dot: dot))
                }
            }
            AppIconPicker()
            Button("Clear Dot", systemImage: "trash", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(store.isEmpty[dot])
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                // The glass style pads this out to 44 points, the height of the dot bar.
                .frame(width: 30, height: 30)
        }
        // The system's glass button, not a glass effect on the label: the menu grows out of it
        // and shrinks back into it. With a separate glass layer, closing the menu left a second,
        // broken rim around the button for a moment.
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .confirmationDialog("Clear this dot?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                store.clear(dot: dot)
            }
        } message: {
            Text("Everything in this dot will be deleted.")
        }
    }
}

/// The app icon, a ring like the dots', comes in every dot's colour, as Tot's does. Orange is
/// the main icon; the others are alternate icons named after their colour.
private struct AppIconPicker: View {
    private static let mainColor = "Orange"
    @State private var choice = Self.currentChoice

    var body: some View {
        Picker("App Icon", systemImage: "circle.circle", selection: $choice) {
            ForEach(DotPalette.colors.indices, id: \.self) { index in
                Text(DotPalette.colors[index].name).tag(index)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: choice) { _, index in
            guard index != Self.currentChoice else { return }
            Task {
                do {
                    try await UIApplication.shared.setAlternateIconName(Self.iconName(for: index))
                } catch {
                    choice = Self.currentChoice
                }
            }
        }
    }

    private static func iconName(for index: Int) -> String? {
        let color = DotPalette.colors[index].name
        return color == mainColor ? nil : "AppIcon-\(color)"
    }

    /// An alternate icon this version no longer has, such as the orange one from before orange
    /// became the main icon, shows as the main icon.
    private static var currentChoice: Int {
        let name = UIApplication.shared.alternateIconName
        return DotPalette.colors.indices.first { iconName(for: $0) == name }
            ?? DotPalette.colors.indices.first { iconName(for: $0) == nil } ?? 0
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
