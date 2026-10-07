import Messages
import Observation
import SwiftUI
import UIKit
import BiteKit

/// Bite in Messages: from the drawer under the message field, the pages, each as a card to send; in
/// the conversation, a card tapped opens to its page, whole, to read. Put down, as Messages puts
/// every app down into its drawer, the page stays, less of it showing (user, 2026-10-07); Bite opened
/// again from the drawer has the pages to send. The pages are the copy Bite keeps for its widgets
/// (see `PageShelf`).
final class MessagesViewController: MSMessagesAppViewController {
    private let model = MessagesModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: MessagesRoot(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        model.send = { [weak self] card in self?.send(card) }
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        model.loadPages()
        model.reading = conversation.selectedMessage?.url.flatMap(PageCard.init(url:))
    }

    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        model.reading = message.url.flatMap(PageCard.init(url:))
    }

    /// Puts the card in the message field, to be sent from there, and the drawer back as it was.
    private func send(_ card: PageCard) {
        guard let conversation = activeConversation,
              let image = card.image(scale: traitCollection.displayScale),
              let message = card.message(image: image) else { return }
        conversation.insert(message)
        if presentationStyle != .compact { requestPresentationStyle(.compact) }
    }
}

/// The pages as Bite last left them for its widgets, the one Bite was on picked, and the card
/// being read.
@MainActor @Observable
final class MessagesModel {
    var pages = Array(repeating: "", count: DotPalette.count)
    var selection = 0
    /// A card tapped in the conversation, its page read whole.
    var reading: PageCard?
    @ObservationIgnored var send: (PageCard) -> Void = { _ in }
    /// Each page's picture in the picker, made once for what's on the page.
    @ObservationIgnored private var pickerImages: [Int: (markdown: String, image: UIImage)] = [:]

    func pickerImage(for page: Int, scale: CGFloat) -> UIImage? {
        let markdown = pages[page]
        if let kept = pickerImages[page], kept.markdown == markdown { return kept.image }
        guard let image = PageCard(page: page, markdown: markdown).pickerImage(scale: scale) else { return nil }
        pickerImages[page] = (markdown, image)
        return image
    }

    func loadPages() {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PageShelf.appGroup) else { return }
        let shelf = PageShelf(folder: folder)
        if let read = shelf.read(), read.count == DotPalette.count { pages = read }
        // The page Bite was last on.
        selection = min(max(shelf.readLastPage() ?? 0, 0), DotPalette.count - 1)
    }
}
