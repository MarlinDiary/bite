import Messages
import SwiftUI
import UIKit
import BiteKit

extension PageCard {
    /// The card's size, in points, as the picture in the message has it.
    static let size = CGSize(width: 300, height: 225)
    /// What the bar under the card says: the page's heading, or, a page that has none, its dot's
    /// name, as a title would be (user, 2026-10-07). Messages draws the bar in its own grey, light
    /// or dark as the person looking has it, and the bubble's tail runs on from it: nothing an app
    /// sends changes the tail's colour, which under the card alone was another colour from it.
    var barTitle: String {
        heading ?? DotPalette.colors[page].pageName
    }

    /// The tallest a card is: Messages shows a card's picture at most 248 points tall in a bubble
    /// 280 wide, and cuts the middle out of a taller one.
    static let tallest: CGFloat = 250
    /// The shortest, for a line or two.
    static let shortest: CGFloat = 100

    /// The page as the picker shows it, every page's the same size, as a picture.
    func pickerImage(scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: PickerCardFace(card: self).environment(\.colorScheme, .light))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// The card as a picture, in light appearance, as the message shows it to everyone: as tall as
    /// its lines, up to `tallest`, with as many as fit there, whole. Laid out as tall as it may be
    /// first, for where those lines end; a line cut off at the bottom left most of a line's room
    /// empty under the last one (user, 2026-10-07).
    func image(scale: CGFloat) -> UIImage? {
        let end = ContentEnd()
        func render(height: CGFloat) -> UIImage? {
            let renderer = ImageRenderer(content: PageCardFace(card: self, height: height, contentEnd: end)
                .environment(\.colorScheme, .light))
            renderer.scale = scale
            return renderer.uiImage
        }
        guard render(height: Self.tallest) != nil else { return nil }
        let height = (PageCardFace.top + end.height + PageCardFace.bottom).rounded(.up)
        return render(height: min(Self.tallest, max(Self.shortest, height)))
    }

    /// The message the card goes in: its picture, what anyone sees, and its address, the page.
    func message(image: UIImage) -> MSMessage? {
        guard let url else { return nil }
        let layout = MSMessageTemplateLayout()
        layout.image = image
        layout.caption = barTitle
        let message = MSMessage()
        message.layout = layout
        message.url = url
        message.summaryText = barTitle
        message.accessibilityLabel = String(localized: "\(DotPalette.colors[page].localizedName) page: \(title)")
        return message
    }
}
