import SwiftUI
import BiteKit

/// The dot bar, as on the phone, with a button at each end, in the colour of the page on screen.
/// The panel's are the "…" button and, once the panel's been dragged away from the ring, a close
/// button; the share extension's, Cancel and Add. Each sits in the panel's corner, concentric with
/// it: as far from the top as from the side, with the corner's radius its own plus that margin.
struct PanelTopBar<Leading: View, Trailing: View>: View {
    @Bindable var store: DotStore
    let onScreen: PageOnScreen
    let leading: (_ ink: Color) -> Leading
    let trailing: (_ ink: Color) -> Trailing
    /// Whether a drag along the top moves the window: the panel's does, the share sheet's doesn't.
    var movesWindow = true

    var body: some View {
        let page = onScreen.page ?? store.selection
        let ink = DotPalette.colors[page].color
        DotSwitcher(selection: $store.selection, highlighted: page)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                leading(ink)
            }
            .overlay(alignment: .trailing) {
                trailing(ink)
            }
            .padding(.horizontal, TopBar.margin)
            .padding(.top, TopBar.margin)
            .frame(maxHeight: .infinity, alignment: .top)
            // Anywhere else along the top, a drag moves the panel, the first one away from the ring.
            .background {
                if movesWindow {
                    Color.clear
                        .contentShape(.rect)
                        .gesture(WindowDragGesture())
                }
            }
            .environment(store)
    }
}

/// The bar's measures.
enum TopBar {
    /// Around the bar and the buttons, from the panel's edges.
    static let margin: CGFloat = 7
    static let height = margin + DotSwitcher.height + margin
    /// The panel's corners, around the buttons'.
    static let cornerRadius = DotSwitcher.height / 2 + margin
}

/// A button at one end of the bar, of the "…" button's size, glass and colour.
struct BarButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let ink: Color
    /// The symbol's size, a phone's, scaled as the bar is: the "…" is 17 points, the cross 14.
    var size: CGFloat = 17
    let action: () -> Void
    private let side = DotSwitcher.height

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * DotSwitcher.scale, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: side, height: side)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// The panel's close button, there once it's been dragged away from the ring.
struct CloseButton: View {
    let placement: PanelPlacement?
    let ink: Color
    let close: () -> Void

    var body: some View {
        ZStack {
            if placement?.isDetached == true {
                BarButton(symbol: "xmark", label: "Close", ink: ink, size: 14, action: close)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: placement?.isDetached)
    }
}

/// The "…" button, which opens the menu below itself.
struct MenuButton: View {
    let ink: Color
    /// Opens the menu below the button, given the button's frame in the bar.
    let showMenu: (CGRect) -> Void
    @State private var frame = CGRect.zero

    var body: some View {
        BarButton(symbol: "ellipsis", label: "More", ink: ink) {
            showMenu(frame)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

/// Whether the panel has been dragged away from the ring, to stand on its own until it's closed.
@Observable
final class PanelPlacement {
    var isDetached = false
}
