import SwiftUI

extension View {
    /// Shows this form as a drawer from the bottom: the system's, in its glass, only as tall as
    /// what's in it, and dragged down or tapped outside to put away.
    func fittedDrawer() -> some View {
        modifier(FittedDrawer())
    }
}

private struct FittedDrawer: ViewModifier {
    /// Everything in the drawer, title included, once it's laid out.
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            // Under the title, the first group sits as far down as the groups sit apart. The form's
            // own margin left nearly twice that, which a drawer this short made look empty.
            .contentMargins(.top, 10, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // A drawer's height leaves out the room by the home indicator, which it adds itself.
                geometry.contentSize.height > 0 ? geometry.contentSize.height + geometry.contentInsets.top : 0
            } action: { _, fitting in
                if fitting > 0 { height = fitting }
            }
            .presentationDetents([.height(height ?? 440)])
            .presentationDragIndicator(.visible)
    }
}
