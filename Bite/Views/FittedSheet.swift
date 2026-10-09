import SwiftUI
import UIKit

extension View {
    /// Shows this form as the system's sheet, only as tall as what's in it. On a phone, a drawer
    /// from the bottom, in its glass, dragged down or tapped outside to put away. On an iPad, a card
    /// in the middle of the screen, as Notes' Add Link is, with ✕ to close it, unless the form has
    /// buttons of its own (`closeButton` false): a drawer pulled up and down from the bottom of an
    /// iPad's screen was a phone's way (user, 2026-10-08). But in an iPad's window as narrow as a
    /// phone, the phone's drawer, as the system's own sheets are there (user, 2026-10-09): see
    /// `sheetIsCard`.
    func fittedSheet(closeButton: Bool = true) -> some View {
        modifier(FittedSheet(closeButton: closeButton))
    }
}

extension EnvironmentValues {
    /// Whether a sheet shown from here is a card in the middle of the window, rather than a drawer
    /// from the bottom (see `fittedSheet`): on an iPad, unless the window is as narrow as a phone,
    /// which the view showing the sheet says. A sheet's own width is the sheet's, not its
    /// window's. On Apple Vision Pro, always: a sheet comes up there as a card in front of its
    /// window.
    @Entry var sheetIsCard = [.pad, .vision].contains(UIDevice.current.userInterfaceIdiom)
}

private struct FittedSheet: ViewModifier {
    let closeButton: Bool
    /// Everything in the sheet, title included, once it's laid out.
    @State private var height: CGFloat?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sheetIsCard) private var isCard

    @ViewBuilder
    func body(content: Content) -> some View {
        let fitted = content
            // Under the title, the first group sits as far down as the groups sit apart. The form's
            // own margin left nearly twice that, which a drawer this short made look empty.
            .contentMargins(.top, 10, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // A drawer's height leaves out the room by the home indicator, which it adds
                // itself.
                geometry.contentSize.height > 0 ? geometry.contentSize.height + geometry.contentInsets.top : 0
            } action: { _, fitting in
                if fitting > 0 { height = fitting }
            }
        if isCard {
            fitted
                .presentationSizing(CardSizing(height: height))
                .background(CardHeight(height: height))
                .toolbar {
                    if closeButton {
                        ToolbarItem(placement: .cancellationAction) {
                            // In the text's colour, as the link card's ✕.
                            Button(role: .close) { dismiss() }
                                .tint(.primary)
                        }
                    }
                }
        } else {
            fitted
                .presentationDetents([.height(height ?? 440)])
                .presentationDragIndicator(.visible)
        }
    }
}

/// A form sheet's width, as tall as what's in it.
private struct CardSizing: PresentationSizing {
    let height: CGFloat?

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        var size = FormPresentationSizing.form.proposedSize(for: root, context: context)
        if let height { size.height = height }
        return size
    }
}

/// Makes the card as tall as what's in it, once that's laid out: a sheet reads its sizing only as
/// it comes up, often before then.
private struct CardHeight: UIViewControllerRepresentable {
    let height: CGFloat?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let height else { return }
        // Once it's in the card's controller.
        DispatchQueue.main.async {
            var card = controller
            while let parent = card.parent { card = parent }
            guard card.presentingViewController != nil, abs(card.preferredContentSize.height - height) > 0.5 else { return }
            let width = card.preferredContentSize.width > 0 ? card.preferredContentSize.width : card.view.bounds.width
            card.preferredContentSize = CGSize(width: width, height: height)
        }
    }
}
