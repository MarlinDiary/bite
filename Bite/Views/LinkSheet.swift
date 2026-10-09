import SwiftUI
import UIKit
import BiteKit

/// A link added or changed on an iPad, in a card in the middle of the window, laid out as Notes'
/// Add Link: an iPad shows no format bar on its keys to change one in (see
/// `PagerContainerView.showsBar`). In a window as narrow as a phone, the phone's drawer from the
/// bottom, as Bite's other sheets are there (see `fit`). The menu over the text's Add Link… and
/// Edit Link…, ⌘K, and a tap on a link while typing bring it up. As on the phone's bar, ✓ or
/// Return keeps the link as typed, and so does a tap outside the card; ✕ leaves it as it was, as
/// does going with no address. A link is taken off with the menu's Remove Link.
///
/// The keys stay up as the card comes and goes, going over to its address and back to the page:
/// they went down and up again, which the user didn't want (2026-10-09). See `show(over:)`.
@MainActor @Observable
final class LinkSheet: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = LinkSheet()

    private(set) var isPresented = false
    /// Whether the card's the phone's drawer, in a narrow window (see `fit`).
    private(set) var isDrawer = false
    /// "Add Link" for a new link, "Edit Link" for one on the page, as on the phone's bar.
    private(set) var title = ""
    var text = ""
    var address = ""
    /// The link, until what becomes of it is settled, and the page it's on.
    @ObservationIgnored private(set) var link: EditorController.PageLink?
    @ObservationIgnored private weak var page: EditorController?
    @ObservationIgnored private weak var card: UIViewController?
    /// Follows the page's window as it's made narrower or wider while the card's up (see `fit`).
    @ObservationIgnored private var widthChange: (any UITraitChangeRegistration)?
    /// The card's own background, while it's a drawer, whose glass shows instead (see `fit`).
    @ObservationIgnored private var cardBackground: UIColor?

    func edit(_ link: EditorController.PageLink, on page: EditorController) {
        // A card still up for another page, in another of Bite's windows, goes, keeping what's
        // typed in it as a tap outside it does.
        if let card, self.page !== page {
            settle(keeping: canFinish)
            card.presentingViewController?.dismiss(animated: true)
            stopFollowingWidth()
            self.card = nil
        }
        settle(keeping: true)
        self.link = link
        self.page = page
        title = link.isNew ? "Add Link" : "Edit Link"
        // Text that only says the address isn't typed: the address stands in for it, in grey,
        // and follows the address until text is typed.
        text = link.saysItsAddress ? "" : link.text
        address = link.address
        isPresented = true
        if card == nil { show(over: page) }
    }

    /// The system's form sheet, over the page and anything already over it.
    ///
    /// The system keeps a page's keys aside while a sheet that's dimmed throughout is over it: it
    /// puts them away before the sheet comes up and brings them back as it goes, whatever comes
    /// to want them in between, so they went down and up again. Naming a size of the sheet up to
    /// which it wouldn't be dimmed, one it never comes to, makes it not dimmed throughout to the
    /// system: the keys are left up, and its address takes them straight from the page. The
    /// sheet is dimmed behind as ever.
    private func show(over page: EditorController) {
        let textView = page.textView
        let responders = sequence(first: textView as UIResponder, next: \.next)
        guard var presenter = responders.first(where: { $0 is UIViewController }) as? UIViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let card = LinkCard(rootView: LinkSheetView(sheet: self).tint(Color(uiColor: textView.tintColor)))
        card.modalPresentationStyle = .formSheet
        card.presentationController?.delegate = self
        // Apple Vision Pro's card comes up in front of its window, the keys in front of both, as
        // they were: the sizes and drawer here are a phone's and an iPad's.
        #if !os(visionOS)
        card.sheetPresentationController?.largestUndimmedDetentIdentifier = Self.neverUndimmed
        fit(card, narrow: textView.traitCollection.horizontalSizeClass == .compact, animated: false)
        widthChange = textView.registerForTraitChanges([UITraitHorizontalSizeClass.self]) { [weak self, weak card] (textView: BiteTextView, _) in
            guard let card else { return }
            self?.fit(card, narrow: textView.traitCollection.horizontalSizeClass == .compact, animated: true)
        }
        #endif
        self.card = card
        presenter.present(card, animated: true)
    }

    #if !os(visionOS)
    /// A size of the card it never comes to (see `show(over:)`).
    private static let neverUndimmed = UISheetPresentationController.Detent.Identifier("bite.linkCard.neverUndimmed")

    /// The drawer's one size, as tall as the card's form (see `fit`).
    static let fitted = UISheetPresentationController.Detent.Identifier("bite.linkCard.fitted")

    /// In a window as narrow as a phone, the card is the phone's drawer from the bottom, as Bite's
    /// other sheets are there (see `fittedSheet`): as tall as its form, which it says as the card's
    /// size, with the grabber to pull it down by, and in the drawer's glass, which the card's own
    /// white hid. The system's own card was as tall as the window there. In a wider window, the
    /// card in the middle, as it was.
    private func fit(_ card: UIViewController, narrow: Bool, animated: Bool) {
        guard let sheet = card.sheetPresentationController else { return }
        let wasDrawer = sheet.detents.contains { $0.identifier == Self.fitted }
        isDrawer = narrow
        guard narrow != wasDrawer else { return }
        if narrow {
            cardBackground = card.view.backgroundColor
        }
        card.view.backgroundColor = narrow ? .clear : cardBackground
        let change = { [weak card] in
            sheet.detents = narrow ? [.custom(identifier: Self.fitted) { [weak card] _ in
                // Its form's height is said as it's laid out, just after the card's up.
                let height = card?.preferredContentSize.height ?? 0
                return height > 0 ? height : 300
            }] : [.large()]
            sheet.prefersGrabberVisible = narrow
        }
        if animated {
            sheet.animateChanges(change)
        } else {
            change()
        }
    }
    #endif

    private func stopFollowingWidth() {
        if let widthChange { page?.textView.unregisterForTraitChanges(widthChange) }
        widthChange = nil
    }

    /// Whether there's an address for the link to go to: ✓ is off without one, as Notes' is.
    var canFinish: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ✓, or Return: the link goes on the page as typed.
    func finish() {
        close(keeping: true)
    }

    /// ✕: the link stays as it was.
    func cancel() {
        close(keeping: false)
    }

    /// The card has gone by a tap outside it or a pull down, which keeps the link as typed if it
    /// has an address to go to.
    func didDismiss() {
        close(keeping: canFinish)
    }

    /// Asks the card to give the keys back to the field that had them (see
    /// `presentationControllerWillDismiss`).
    private(set) var keysBack = 0

    /// The keys go back to the page, the caret after the link, or where it was, before the card
    /// goes: from its field straight to the page, they stay up.
    private func close(keeping: Bool) {
        let page = page
        settle(keeping: keeping)
        page?.focus()
        isPresented = false
        if let card, card.presentingViewController != nil, !card.isBeingDismissed {
            card.presentingViewController?.dismiss(animated: true)
        }
        stopFollowingWidth()
        card = nil
    }

    private func settle(keeping: Bool) {
        guard let link, let page else { return }
        self.link = nil
        if keeping { page.setLink(link, text: text, destination: address) }
    }

    /// A tap outside or a pull down: the keys go to the page now. The system takes them from the
    /// card's field before it says the card is going, and they'd go down and up again.
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        page?.focus()
        return true
    }

    /// A pull down let go of short of going: the card stays out, and takes the keys back.
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        presentationController.presentedViewController.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
            if context.isCancelled { self?.keysBack += 1 }
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didDismiss()
    }
}

/// The card's controller. As a drawer, in a narrow window, it follows its form in height as the
/// card does, the form saying it as the card's size (see `LinkSheet.fit`).
private final class LinkCard<Content: View>: UIHostingController<Content> {
    #if !os(visionOS)
    override var preferredContentSize: CGSize {
        didSet {
            guard preferredContentSize.height != oldValue.height, let sheet = sheetPresentationController,
                  sheet.detents.contains(where: { $0.identifier == LinkSheet.fitted }) else { return }
            sheet.animateChanges { sheet.invalidateDetents() }
        }
    }
    #endif
}

/// The card, laid out as Notes' Add Link: where the link goes, then its text, each in a group of
/// its own under its name, ✕ and ✓ above. The user found the phone bar's two rows joined in one
/// group, with their symbols, ugly here (2026-10-08).
struct LinkSheetView: View {
    @Bindable var sheet: LinkSheet
    @FocusState private var row: Row?
    /// The field the keys were last in, to give them back to.
    @State private var lastRow = Row.address

    private enum Row {
        case address, text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link To") {
                    field(text: $sheet.address) {
                        TextField("Enter an address", text: $sheet.address)
                            .focused($row, equals: .address)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .onSubmit { row = .text }
                    }
                }
                Section("Text") {
                    field(text: $sheet.text) {
                        // Empty, the text is the address, which stands in for it.
                        TextField(sheet.address.isEmpty ? "Optional" : sheet.address, text: $sheet.text)
                            .focused($row, equals: .text)
                            // Link text is mostly mid-sentence.
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit { if sheet.canFinish { sheet.finish() } }
                    }
                }
            }
            // A card's way of saying its height, which a drawer follows too: the system shows this
            // one, either way (see `LinkSheet.fit`).
            .fittedSheet(closeButton: false)
            .environment(\.sheetIsCard, true)
            // As a drawer, its glass shows through, as the phone's drawers' does (see
            // `LinkSheet.fit`): the white behind the form hid it. Apple Vision Pro's is glass.
            #if !os(visionOS)
            .containerBackground(sheet.isDrawer ? AnyShapeStyle(.clear) : AnyShapeStyle(.background), for: .navigation)
            #endif
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // In the text's colour, as Notes' is, not the page's.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { sheet.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .tint(.primary)
                }
                // Off with no address to go to, as Notes' is.
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { sheet.finish() }
                        .disabled(!sheet.canFinish)
                }
            }
        }
        // The keys go to the address, as on the phone's bar.
        .onAppear { row = .address }
        .onChange(of: row) { _, row in
            if let row { lastRow = row }
        }
        .onChange(of: sheet.keysBack) { row = lastRow }
    }

    /// A field with a button to empty it, as Notes' has.
    private func field(text: Binding<String>, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            content()
            if !text.wrappedValue.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text.wrappedValue = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
