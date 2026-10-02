import SwiftUI
import UIKit
import BiteKit

/// Settings, from the "…" menu.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DotStore.self) private var store
    @State private var syncsWithICloud = Preferences.syncsWithICloud
    @State private var checksSpelling = Preferences.checksSpelling
    @State private var playsHaptics = Preferences.playsHaptics
    @State private var isConfirmingReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sync with iCloud", isOn: $syncsWithICloud)
                } footer: {
                    Text("Pages stay the same on every device signed in to your iCloud account.")
                }
                Section {
                    Toggle("Check Spelling", isOn: $checksSpelling)
                    Toggle("Haptics", isOn: $playsHaptics)
                }
                AppIconPicker()
                Section {
                    Button("Reset All Pages", role: .destructive) {
                        isConfirmingReset = true
                    }
                    .confirmationDialog("Reset all pages?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                        Button("Reset All Pages", role: .destructive) {
                            store.resetAllPages()
                            dismiss()
                        }
                    } message: {
                        Text(PageReset.message)
                    }
                }
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
        .onChange(of: syncsWithICloud) {
            Preferences.syncsWithICloud = syncsWithICloud
        }
        .onChange(of: checksSpelling) {
            Preferences.checksSpelling = checksSpelling
        }
        .onChange(of: playsHaptics) {
            Preferences.playsHaptics = playsHaptics
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
