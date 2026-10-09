import AppKit
import BiteKit

/// A link under the pointer: a pill floating under it with where it goes and Edit, which brings
/// up the link card (see `LinkCard`). The address is only said, not pressed: the link's text
/// itself opens on a click. The pill comes as the pointer comes onto a link and goes as it leaves,
/// unless it's on its way to the pill (the user, 2026-10-04: no waiting).
@MainActor
final class LinkBubble: NSView {
    static let height: CGFloat = 28
    /// Between the pill and the link.
    static let gap: CGFloat = 4
    private static let maxAddressWidth: CGFloat = 220

    private let glass = NSGlassEffectView()
    private let addressLabel = NSTextField(labelWithString: "")
    private let editButton = HandButton()
    /// Up, or on its way up: set as the pill comes, before it has faded in, and cleared as it's
    /// told to go, before it has faded out.
    private(set) var isShown = false
    /// Counts comings and goings, so a fade finishing late doesn't hide a pill shown again since.
    private var shows = 0
    private(set) var link: EditorController.PageLink?
    private weak var page: EditorController?
    /// Edit, pressed.
    var onEdit: (EditorController.PageLink, EditorController) -> Void = { _, _ in }
    /// The pointer came onto the pill, or left it, and where it is then, in the window.
    var onHoverChange: (Bool, NSPoint) -> Void = { _, _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass.cornerRadius = Self.height / 2
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        addressLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        addressLabel.textColor = .secondaryLabelColor
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(addressLabel)
        editButton.isBordered = false
        editButton.setButtonType(.momentaryChange)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.target = self
        editButton.action = #selector(editPressed)
        editButton.attributedTitle = NSAttributedString(string: String(localized: "Edit"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        editButton.setAccessibilityLabel(String(localized: "Edit link"))
        content.addSubview(editButton)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            addressLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            addressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxAddressWidth),
            editButton.leadingAnchor.constraint(equalTo: addressLabel.trailingAnchor, constant: 10),
            editButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            editButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows `link`'s pill under its text, drawn at `anchor` in the superview, as a tooltip sits,
    /// or over it with no room below, in the superview's flipped coordinates.
    func show(_ link: EditorController.PageLink, on page: EditorController, anchor: NSRect, topClearance: CGFloat) {
        self.link = link
        self.page = page
        addressLabel.stringValue = link.address
        guard let superview else { return }
        let width = min(fittingSize.width, superview.bounds.width - 2 * LinkCard.margin)
        let x = min(max(anchor.minX, LinkCard.margin), superview.bounds.width - width - LinkCard.margin)
        var y = anchor.maxY + Self.gap
        if y + Self.height > superview.bounds.height - LinkCard.margin { y = max(anchor.minY - Self.gap - Self.height, topClearance) }
        frame = NSRect(x: x, y: y, width: width, height: Self.height)
        // Laid out before the pointer's shapes are worked out: Edit moves with the address's length.
        layoutSubtreeIfNeeded()
        window?.invalidateCursorRects(for: self)
        window?.invalidateCursorRects(for: editButton)
        shows += 1
        guard !isShown else { return }
        isShown = true
        // Fading in, from where it is; a pill still fading out comes back from there.
        if isHidden {
            alphaValue = 0
            isHidden = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
    }

    /// Gone at once, as when Edit on it brings the card up in its place.
    func hideNow() {
        guard isShown else { return }
        isShown = false
        shows += 1
        isHidden = true
        alphaValue = 1
        link = nil
        page = nil
    }

    /// Fades out, and is gone once it has.
    func hide() {
        guard isShown else { return }
        isShown = false
        shows += 1
        let show = shows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shows == show, !self.isShown else { return }
                self.isHidden = true
                self.link = nil
                self.page = nil
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// The pointer over the pill is the pill's: an arrow, the address being only said, and a hand
    /// over Edit, which is pressed. The page's I-beam, and its hand for the link above, showed
    /// through it.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func setCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        (editButton.frame.contains(editButton.superview?.convert(point, from: self) ?? point) ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        setCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        setCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        setCursor(for: event)
        onHoverChange(true, event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false, event.locationInWindow)
    }

    /// A click on the pill beside Edit is the pill's, not the page's.
    override func mouseDown(with event: NSEvent) {}

    @objc private func editPressed() {
        guard let link, let page else { return }
        onEdit(link, page)
    }

    #if DEBUG
    var addressForTesting: String { addressLabel.stringValue }
    var addressIsPlainTextForTesting: Bool { !addressLabel.isSelectable && !addressLabel.isEditable }
    var editFontForTesting: NSFont? { editButton.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont }

    /// As Edit on the pill does.
    func editForTesting() {
        editPressed()
    }
    #endif
}

/// A button the pointer turns into a hand over, as over a link, which is what it's about.
private final class HandButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
