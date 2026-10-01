import SwiftUI
import UIKit
import BiteKit

/// Settings, from the "…" menu.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AppIconPicker()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The app icon, a ring like the dots', comes in every dot's colour, as Tot's does. Orange is
/// the main icon; the others are alternate icons named after their colour.
private struct AppIconPicker: View {
    private static let mainColor = "Orange"
    @State private var choice = Self.currentChoice

    var body: some View {
        Picker("App Icon", selection: $choice) {
            ForEach(DotPalette.colors.indices, id: \.self) { index in
                Label {
                    Text(DotPalette.colors[index].name)
                } icon: {
                    // The size and ring of a dot in the dot bar.
                    Circle()
                        .strokeBorder(DotPalette.colors[index].color, lineWidth: 3)
                        .frame(width: 18, height: 18)
                }
                .tag(index)
            }
        }
        .pickerStyle(.inline)
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
