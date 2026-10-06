import SwiftUI
import UIKit
import BiteKit

/// Settings, from the "…" menu: a drawer from the bottom (see `fittedDrawer`).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DotStore.self) private var store
    @State private var syncsWithICloud = Preferences.syncsWithICloud
    @State private var showsInSpotlight = Preferences.showsInSpotlight
    @State private var checksSpelling = Preferences.checksSpelling
    @State private var playsHaptics = Preferences.playsHaptics
    @State private var locksPortrait = Preferences.locksPortrait
    @State private var keepsScreenOn = Preferences.keepsScreenOn
    @State private var isConfirmingReset = false

    var body: some View {
        NavigationStack {
            // Each section answers one question, with no header to say so: where the pages go, how
            // Bite is to use, how it looks, and starting over.
            Form {
                Section {
                    Toggle("Sync with iCloud", isOn: $syncsWithICloud)
                    Toggle("Show in Spotlight", isOn: $showsInSpotlight)
                }
                Section {
                    Toggle("Check Spelling", isOn: $checksSpelling)
                    Toggle("Haptics", isOn: $playsHaptics)
                    // An iPad's Bite is a window of any shape, which no way up suits better.
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Toggle("Lock to Portrait", isOn: $locksPortrait)
                    }
                    Toggle("Keep Screen On", isOn: $keepsScreenOn)
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
            .fittedDrawer()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: syncsWithICloud) {
            Preferences.syncsWithICloud = syncsWithICloud
        }
        .onChange(of: showsInSpotlight) {
            Preferences.showsInSpotlight = showsInSpotlight
        }
        .onChange(of: checksSpelling) {
            Preferences.checksSpelling = checksSpelling
        }
        .onChange(of: playsHaptics) {
            Preferences.playsHaptics = playsHaptics
        }
        .onChange(of: locksPortrait) {
            Preferences.locksPortrait = locksPortrait
        }
        .onChange(of: keepsScreenOn) {
            Preferences.keepsScreenOn = keepsScreenOn
        }
    }
}

/// The app icon, a ring like the dots', comes in every dot's colour, as Tot's does. Orange is
/// the main icon; the others are alternate icons named after their colour. They're the dot bar's
/// rings, in a row, with the icon's own filled in. As a list, one colour to a line, they made
/// Settings nearly as tall as the screen.
private struct AppIconPicker: View {
    private static let mainColor = "Orange"
    @State private var choice = Self.currentChoice

    var body: some View {
        Section {
            LabeledContent("App Icon") {
                HStack(spacing: 0) {
                    ForEach(DotPalette.colors.indices, id: \.self) { index in
                        Button {
                            choice = index
                        } label: {
                            // A dot's size and spacing in the dot bar, and as tall to press, though
                            // the row stands only as tall as a switch's.
                            DotIndicator(ink: DotPalette.colors[index], isSelected: choice == index)
                                .frame(width: 30, height: 44)
                                .contentShape(.rect)
                                .padding(.vertical, -11)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(DotPalette.colors[index].name)
                        .accessibilityAddTraits(choice == index ? .isSelected : [])
                    }
                }
            }
        }
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
