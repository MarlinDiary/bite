import AppKit
import BiteKit

/// A link being changed, in a card floating by its text, as the phone's rides on the keys: the
/// link's text in one row and where it goes in the other, and nothing else. The page shows the
/// link as it's typed. Return moves on from the text to the address, and from there puts the link
/// on the page; Esc puts it back as it was; and the keys going elsewhere, to the page clicked or
/// another page, keep it as typed: it's on the page already. No Cancel or Done, as the phone has:
/// on the Mac a click outside is enough (the user, 2026-10-04). The panel brings it up for ⌘K,
/// Edit Link in a link's menu, and Edit on the pill over a link under the pointer (see
/// `PanelController`, `LinkBubble`).
@MainActor
final class LinkCard: NSView, NSTextFieldDelegate {
    /// The rows: the link's text, and where it goes.
    enum Row {
        case name, address
    }

    /// The card's height: the two rows.
    static let height: CGFloat = rowHeight * 2
    /// The card's width, as far as the panel allows: it floats by the link rather than filling
    /// the panel, which stretched it as wide as the panel was dragged.
    static let width: CGFloat = 320
    /// Around the card, from the panel's edges.
    static let margin: CGFloat = 8
    /// Between the card and the link.
    static let gap: CGFloat = 8
    private static let rowHeight: CGFloat = 48

    private let glass = NSGlassEffectView()
    private let nameField = LinkField()
    private let addressField = LinkField()
    /// The link being changed, while it is, and the page it's on.
    private(set) var editingLink: EditorController.PageLink?
    private weak var page: EditorController?
    var isEditingLink: Bool { editingLink != nil }
    /// Called as the card comes and goes.
    var onShownChange: (Bool) -> Void = { _ in }
    /// How far down the superview the card may go: under the dot bar.
    var topClearance: CGFloat = 0
    /// Set once what becomes of the link is settled, kept as typed or put back, while the keys go
    /// back to the page: the keys' going then leaves it be.
    private var isSettled = false
    /// What the rows are typed in, the card's own: its caret and selection take the page's colour,
    /// as the page's own do. The window's shared one had the system's.
    let fieldEditor: LinkFieldEditor = {
        let editor = LinkFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.allowsUndo = true
        return editor
    }()

    /// Whether `client` is one of the card's rows, which type in `fieldEditor`.
    func owns(_ client: Any?) -> Bool {
        (client as AnyObject?) === nameField || (client as AnyObject?) === addressField
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glass.cornerRadius = 18
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content

        let nameStack = makeRow(symbol: "character.cursor.ibeam", field: nameField, placeholder: "Text", title: "Text")
        let addressStack = makeRow(symbol: "link", field: addressField, placeholder: "Address", title: "Address")
        // Tab moves between the rows, and Return (see `control(_:textView:doCommandBy:)`).
        nameField.nextKeyView = addressField
        addressField.nextKeyView = nameField
        // Between the rows, from where the text starts, as a list's lines are.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        for view in [nameStack, addressStack, divider] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            content.topAnchor.constraint(equalTo: glass.topAnchor),
            content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),

            nameStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            nameStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            nameStack.centerYAnchor.constraint(equalTo: content.topAnchor, constant: Self.rowHeight / 2),
            addressStack.leadingAnchor.constraint(equalTo: nameStack.leadingAnchor),
            addressStack.trailingAnchor.constraint(equalTo: nameStack.trailingAnchor),
            addressStack.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.rowHeight / 2),

            divider.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: nameStack.trailingAnchor),
            divider.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A row: a symbol saying what it holds, where a button would be, and its field.
    private func makeRow(symbol: String, field: NSTextField, placeholder: String, title: String) -> NSStackView {
        let icon = NSImageView(image: Self.symbol(symbol))
        icon.contentTintColor = .labelColor
        icon.imageAlignment = .alignCenter
        icon.setAccessibilityElement(false)

        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityLabel(title)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, field])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 44),
        ])
        return stack
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        return image.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? image
    }

    // MARK: The link

    /// The link's text as it stands, nothing if it's blank: then it's the address.
    private var name: String {
        let name = nameField.stringValue
        return name.allSatisfy(\.isWhitespace) ? "" : name
    }

    private var address: String {
        addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text left empty is the address, which stands in for it, in grey.
    private func showAddress() {
        nameField.placeholderString = address.isEmpty ? "Text" : address
    }

    /// Shows `link` in the card, its text above where it goes, to change, and moves the keys over
    /// to its address, the caret at its end. Text that only says the address isn't typed: the
    /// address stands in for it, in grey, and follows the address until text is typed.
    func edit(_ link: EditorController.PageLink, on page: EditorController) {
        if isEditingLink { finish() }
        editingLink = link
        self.page = page
        isSettled = false
        fieldEditor.insertionPointColor = page.textView.insertionPointColor
        fieldEditor.selectionColor = page.textView.selectionColor
        nameField.stringValue = link.saysItsAddress ? "" : link.text
        addressField.stringValue = link.address
        showAddress()
        page.textView.showLinkTarget(link.range)
        place()
        setShown(true)
        focus(addressField)
    }

    /// Moves the keys to `field`, the caret at the end of its text: AppKit selects it all, as for
    /// a Tab, which typing would replace.
    private func focus(_ field: NSTextField) {
        window?.makeFirstResponder(field)
        let end = field.stringValue.utf16.count
        field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
    }

    /// Puts the card by the link's text, above it, or below it with no room above, as far along
    /// as the link starts, within the panel. Again as the page scrolls or the panel is resized.
    func place() {
        guard let link = editingLink, let page, let superview else { return }
        let start = NSRange(location: link.range.location, length: min(link.range.length, 1))
        guard let drawn = page.textView.anchorFrame(for: start) else { return }
        let anchor = superview.convert(drawn, from: page.textView)
        let width = min(Self.width, superview.bounds.width - 2 * Self.margin)
        let x = min(max(anchor.minX - 10, Self.margin), superview.bounds.width - width - Self.margin)
        var y = anchor.minY - Self.gap - Self.height
        if y < topClearance { y = anchor.maxY + Self.gap }
        y = min(max(y, topClearance), superview.bounds.height - Self.height - Self.margin)
        frame = NSRect(x: x, y: y, width: width, height: Self.height)
    }

    /// Typed in either row: the link as it stands shows on the page, lit. Not while an input
    /// method composes the text: its letters aren't the text yet.
    func controlTextDidChange(_ notification: Notification) {
        if notification.object as AnyObject? === addressField { showAddress() }
        showLinkAsTyped()
    }

    private func showLinkAsTyped() {
        guard let link = editingLink, let page else { return }
        if let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor, editor.hasMarkedText() { return }
        page.textView.showLinkTarget(page.previewLink(link, text: name, destination: address))
    }

    /// Return in the text moves on to the address, and in the address puts the link on the page;
    /// Esc puts it back as it was.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === nameField {
                focus(addressField)
            } else {
                finish()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    /// The window's keys went to `responder`. Gone from the card, to the page clicked or anywhere
    /// else, they leave the link as typed, as Done does. Between the rows they stay the card's: on
    /// the way from one row to the other the window itself holds them for a moment.
    func keysWent(to responder: NSResponder?) {
        guard isEditingLink else { return }
        if responder === nameField || responder === addressField || responder === window { return }
        if let editor = responder as? NSTextView, editor.isFieldEditor, !(editor is BiteTextView) { return }
        apply()
        end()
    }

    /// Puts the link's text and address on the page as they stand, as one edit, to undo all at
    /// once: what was shown as they were typed goes back first. Both left as they were change
    /// nothing, with nothing to undo.
    private func apply() {
        guard let link = editingLink, let page, !isSettled else { return }
        isSettled = true
        page.textView.showLinkTarget(nil)
        page.endLinkPreview()
        page.setLink(link, text: name, destination: address)
    }

    /// Return in the address: the link goes on the page as it stands, and the keys back to the
    /// page.
    func finish() {
        let page = page
        apply()
        end()
        page?.focus()
    }

    /// Esc: the link goes back as it was, and the keys back to the page, the caret where it was.
    func cancel() {
        let page = page
        page?.textView.showLinkTarget(nil)
        page?.endLinkPreview()
        isSettled = true
        end()
        page?.focus()
    }

    /// The card goes, and what was shown as the link was typed, if it wasn't put on the page, goes
    /// back as it was.
    private func end() {
        guard editingLink != nil else { return }
        editingLink = nil
        page?.textView.showLinkTarget(nil)
        page?.endLinkPreview()
        page = nil
        setShown(false)
    }

    /// Up, or on its way up: set as the card comes, and cleared as it's told to go, before it's
    /// gone from the screen.
    private(set) var isShown = false
    /// Counts comings and goings, so a going finishing late doesn't hide a card shown again since.
    private var shows = 0

    /// The card comes as a popover does, growing a little into its place as it fades in, and goes
    /// fading as it shrinks back, never bouncing. Fading alone didn't show: the glass is drawn
    /// whole whatever the card's opacity, and it popped in and out.
    private func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        shows += 1
        let show = shows
        onShownChange(shown)
        guard let layer else {
            isHidden = !shown
            return
        }
        defer { window?.invalidateCursorRects(for: self) }
        let duration = (shown ? 0.18 : 0.12) * Self.animationSlowdown
        let small = Self.scaled(layer, by: shown ? 0.96 : 0.98)
        layer.removeAnimation(forKey: Self.showKey)
        let grow = CABasicAnimation(keyPath: "transform")
        let fade = CABasicAnimation(keyPath: "opacity")
        if shown {
            isHidden = false
            grow.fromValue = NSValue(caTransform3D: small)
            grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            fade.fromValue = 0
            fade.toValue = 1
        } else {
            grow.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            grow.toValue = NSValue(caTransform3D: small)
            fade.fromValue = 1
            fade.toValue = 0
        }
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shows == show else { return }
                if !shown { self.isHidden = true }
                self.layer?.removeAnimation(forKey: Self.showKey)
            }
        }
        layer.add(group, forKey: Self.showKey)
        CATransaction.commit()
    }

    private static let showKey = "show"
    /// Stretches the card's coming and going, to see them. For snapshots.
    static var animationSlowdown: Double = 1

    /// The layer's transform scaled by `scale` about its middle. AppKit puts a view's layer's
    /// anchor at its corner, which a plain scale would shrink toward.
    private static func scaled(_ layer: CALayer, by scale: CGFloat) -> CATransform3D {
        let bounds = layer.bounds
        let anchor = layer.anchorPoint
        let x = bounds.width * (0.5 - anchor.x), y = bounds.height * (0.5 - anchor.y)
        var transform = CATransform3DMakeTranslation(x, y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -x, -y, 0)
    }

    /// The pointer over the card: an I-beam over the rows' text, typed in, and an arrow elsewhere
    /// on it. The shield under it, and the page under that, hear the pointer here too.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        for field in [nameField, addressField] {
            addCursorRect(convert(field.bounds, from: field), cursor: .iBeam)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func setCursor(for event: NSEvent) {
        guard isShown else { return }
        let point = convert(event.locationInWindow, from: nil)
        let overText = [nameField, addressField].contains { convert($0.bounds, from: $0).contains(point) }
        (overText ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        setCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        setCursor(for: event)
    }

    /// Every click within the card is the card's: none reaches the page behind it, which would
    /// take the keys and put the card away. Going, it takes none.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isShown, frame.contains(point), !isHidden else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}

    #if DEBUG
    var nameForTesting: String { nameField.stringValue }
    /// The colour of the caret typed with in the card, and of what's selected there.
    var caretColorForTesting: NSColor { fieldEditor.insertionPointColor }
    /// Whether either row is drawn vibrant on the glass.
    var rowsAreVibrantForTesting: Bool { nameField.allowsVibrancy || addressField.allowsVibrancy }
    var selectionColorForTesting: NSColor? { fieldEditor.selectedTextAttributes[.backgroundColor] as? NSColor }
    var addressForTesting: String { addressField.stringValue }
    var namePlaceholderForTesting: String { nameField.placeholderString ?? "" }

    /// The row the keys are on, while they're on the card.
    var rowWithKeysForTesting: Row? {
        let responder = window?.firstResponder
        let field = (responder as? NSTextView)?.delegate as? NSTextField ?? responder as? NSTextField
        return field === nameField ? .name : field === addressField ? .address : nil
    }

    /// As typing `text` in the link's text row does, the keys brought there first.
    func typeNameForTesting(_ text: String) {
        window?.makeFirstResponder(nameField)
        nameField.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
    }

    /// As typing `text` in the link's address row does, the keys brought there first.
    func typeAddressForTesting(_ text: String) {
        window?.makeFirstResponder(addressField)
        addressField.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: addressField))
    }

    /// As Return in the row the keys are on does.
    func returnForTesting() {
        let field = rowWithKeysForTesting == .name ? nameField : addressField
        _ = control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    }

    /// As Esc in the card does.
    func escapeForTesting() {
        _ = control(addressField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    }
    #endif
}

/// Over the page while a link card is up, under the card: the page takes no clicks or scrolling
/// meanwhile, as behind a popover, and a click on it only puts the card away. The pointer over it
/// is an arrow, not the page's I-beam.
@MainActor
final class LinkShield: NSView {
    var onClick: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !frame.contains(point) ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    /// Whether the pointer is on the shield itself, not on the card over it: its tracking area
    /// hears the pointer under the card too.
    private func isUnderPointer(_ event: NSEvent) -> Bool {
        !isHidden && window?.contentView?.hitTest(event.locationInWindow) === self
    }

    override func cursorUpdate(with event: NSEvent) {
        if isUnderPointer(event) { NSCursor.arrow.set() }
    }

    override func mouseMoved(with event: NSEvent) {
        if isUnderPointer(event) { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick()
    }

    override func otherMouseDown(with event: NSEvent) {
        onClick()
    }

    override func scrollWheel(with event: NSEvent) {}
}

/// A row's field. Drawn plain, not vibrant, as the field editor draws it while it has the keys:
/// on the glass, the field drew its grey placeholder in the text's black whenever the keys were
/// elsewhere (user, 2026-10-05).
private final class LinkField: NSTextField {
    override var allowsVibrancy: Bool { false }
}

/// The link card's field editor, which keeps its selection in the page's colour: a row's cell sets
/// the editor up as the keys come to it, and put the system's colour back each time.
@MainActor
final class LinkFieldEditor: NSTextView {
    var selectionColor: NSColor? {
        didSet { selectedTextAttributes = super.selectedTextAttributes }
    }

    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { super.selectedTextAttributes }
        set {
            var attributes = newValue
            if let selectionColor { attributes[.backgroundColor] = selectionColor }
            super.selectedTextAttributes = attributes
        }
    }
}
