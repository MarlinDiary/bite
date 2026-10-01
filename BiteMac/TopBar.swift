import SwiftUI
import BiteKit

/// The dot bar, as on the phone, with the "…" button at its end. The button sits in the panel's
/// corner, concentric with it: as far from the top as from the side, with the corner's radius
/// its own plus that margin. Once the panel's been dragged away from the ring, a close button
/// sits in the other corner the same way.
struct TopBar: View {
    @Bindable var store: DotStore
    let onScreen: PageOnScreen
    let placement: PanelPlacement
    let close: () -> Void
    /// Opens the menu below the button, given the button's frame in the bar.
    let showMenu: (CGRect) -> Void

    /// Around the bar and the button, from the panel's edges.
    static let margin: CGFloat = 7
    static let height = margin + DotSwitcher.height + margin
    /// The panel's corners, around the button's.
    static let cornerRadius = DotSwitcher.height / 2 + margin

    var body: some View {
        let page = onScreen.page ?? store.selection
        DotSwitcher(selection: $store.selection, highlighted: page)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                if placement.isDetached {
                    CloseButton(ink: DotPalette.colors[page].color, close: close)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .trailing) {
                MenuButton(ink: DotPalette.colors[page].color, showMenu: showMenu)
            }
            .animation(.easeOut(duration: 0.15), value: placement.isDetached)
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.margin)
            .frame(maxHeight: .infinity, alignment: .top)
            // Anywhere else along the top, a drag moves the panel, the first one away from the ring.
            .background {
                Color.clear
                    .contentShape(.rect)
                    .gesture(WindowDragGesture())
            }
            .environment(store)
    }
}

/// Of the "…" button's size, glass and colour.
private struct CloseButton: View {
    let ink: Color
    let close: () -> Void
    private let size = DotSwitcher.height

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 14 * DotSwitcher.scale, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Close")
    }
}

/// As tall as the dot bar, as on the phone, and of the same glass.
private struct MenuButton: View {
    /// The colour of the page on screen, which the phone's button takes from the tint.
    let ink: Color
    let showMenu: (CGRect) -> Void
    @State private var frame = CGRect.zero
    private let size = DotSwitcher.height

    var body: some View {
        Button {
            showMenu(frame)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17 * DotSwitcher.scale, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}
