import UIKit
import BiteKit

/// Formatting buttons above the keyboard. All seven editors share one bar, so it stays put
/// when you swipe to another dot while typing. The pager places it on top of the keys.
///
/// Links are changed in it too, while a page is being edited: the glass grows up from the keys, the
/// link's text over where it goes, under a row that says what's being done, Add Link or Edit Link,
/// between buttons to cancel and to finish, and the keys move over to them as they are (see
/// `editLink`).
final class FormatBar: UIView, UITextViewDelegate, UIGestureRecognizerDelegate {
    static let shared = FormatBar()
    /// The glass capsule and the space around it, down to the top of the keys.
    static let height: CGFloat = 60
    /// A row of the glass, the capsule's height. A link being changed takes two, under its buttons.
    private static let rowHeight: CGFloat = 48
    /// The row with a link's buttons, to cancel and to finish.
    private static let buttonRowHeight: CGFloat = 44
    /// How tall the link's rows stand: two rows, or more as an address wraps.
    private var rowsHeight: CGFloat = 2 * rowHeight
    /// How tall the bar stands now: taller while a link is being changed in it, the link's rows
    /// in the capsule's place and its buttons above them.
    var height: CGFloat { showsLink ? Self.height - Self.rowHeight + Self.buttonRowHeight + rowsHeight : Self.height }
    /// The glass, which the heading button's menu comes out of, as a toolbar turns into its menus.
    private weak var glassView: UIVisualEffectView?
    /// Called as the bar grows for a link, or goes back down, so the pager moves it and makes room
    /// for it on the page.
    var onHeightChange: (() -> Void)?
    weak var editor: EditorController?
    private var buttons: [FormatAction: BarButton] = [:]
    /// The buttons' row, which scrolls past the first six.
    private var buttonScroll: UIScrollView?
    /// The formatting buttons and the one putting the keys away, which a link's rows take the
    /// place of.
    private var formatViews: [UIView] = []
    private var glassHeight: NSLayoutConstraint!
    /// The link's buttons, over its text: one leaving it as it was, one putting it on the page,
    /// and between them what's being done, so the rows below read as a link's.
    private let buttonRow = UIView()
    private let linkTitle = UILabel()
    /// A link's rows: its text, in a row the glass grows above the formatting buttons, and where it
    /// goes, in their place.
    enum LinkRow {
        case name, address
    }
    /// Both rows, with their symbols, the line between them, and what stands in for empty text.
    private let linkRows = LinkRowsView()
    private var rowsHeightConstraint: NSLayoutConstraint!
    private let nameIcon = UIImageView()
    private let addressIcon = UIImageView()
    private let nameLabel = UILabel()
    private let addressLabel = UILabel()
    private let divider = Hairline()
    private var nameIconY: NSLayoutConstraint!
    private var addressIconY: NSLayoutConstraint!
    private var dividerY: NSLayoutConstraint!
    /// Where the text row's last line ends and the address row's first line starts, in the text
    /// view: between them is the gap the rows meet in, under the text row's text and over the
    /// address row's.
    private var nameLineBottom: CGFloat = 0
    private var addressLineTop: CGFloat = 0
    /// The one text view for both rows: the link's text on its first line, where it goes on its
    /// second, and the keys on whichever line the caret is on. A tap on the other row only moves
    /// the caret, as a tap in any text does. With a field for each row, or one moved between them,
    /// the keys were rebuilt or told of new text at every move, 60–170 ms on the phone (iOS 27.2).
    private let linkText = UITextView()
    private var textAttributes: [NSAttributedString.Key: Any] = [:]
    /// A line's height at the type size, and the space above and below one that makes a row.
    private var lineHeight: CGFloat = 0
    private var linePadding: CGFloat = 0
    /// The rows' text as typed.
    private var nameText = ""
    private var addressText = ""
    /// The link being changed, while it is, and the page it's on: the keys are on its text or on
    /// its address.
    private(set) var editingLink: EditorController.PageLink?
    private weak var linkPage: EditorController?
    var isEditingLink: Bool { editingLink != nil }
    /// Whether the link's rows are up in place of the buttons.
    private var showsLink = false
    /// Set once what becomes of the link is settled, kept as typed or put back, while the keys go
    /// back to a page: the text view giving them up then leaves it be, and the bar lets it go once
    /// the page has them (`pageTookKeys`).
    private var isLinkSettled = false

    private init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.height))
        backgroundColor = .clear

        // Interactive, as the dot bar is: the glass swells under a finger and springs back, over a
        // link's rows too (user, 2026-10-05), though it stands still a few frames as the caret
        // moves between them: iOS holds the main thread about 30 ms telling the keys, and the
        // glass's give runs on it a frame at a time.
        #if os(visionOS)
        // Not shown on Apple Vision Pro, whose keys float apart from the page.
        let glass = UIVisualEffectView(effect: nil)
        #else
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glass = UIVisualEffectView(effect: effect)
        #endif
        glassView = glass
        glass.translatesAutoresizingMaskIntoConstraints = false
        // A capsule, and with a link's rows a card, its corners the capsule's ends.
        glass.cornerConfiguration = .capsule(maximumRadius: Self.rowHeight / 2)
        // The link's text comes in from above as the glass grows up to it, not over the glass.
        glass.contentView.clipsToBounds = true
        addSubview(glass)

        let scroll = FadingScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Two pages of six, a swipe turning from one to the other, rather than a row slid along.
        scroll.isPagingEnabled = true
        buttonScroll = scroll
        let buttons = FormatAction.allCases.filter { $0 != .dismiss }.map { makeButton(for: $0, fixedWidth: false) }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let dismiss = makeButton(for: .dismiss, fixedWidth: false)
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        // Seven across the bar, evenly: the first six buttons and the one putting the keys away,
        // the rest of the buttons a scroll away. No wider than 60 points, so a wider bar, an
        // iPad's, shows more, and no narrower than a button on its own.
        let sevenAcross = dismiss.widthAnchor.constraint(equalTo: glass.contentView.widthAnchor, multiplier: 1.0 / 7,
                                                         constant: -2 * Self.edgeInset / 7)
        sevenAcross.priority = .defaultHigh
        // Where the first button is, for what stands in its place while a link is changed.
        let firstSlot = UILayoutGuide()
        glass.contentView.addLayoutGuide(firstSlot)
        glass.contentView.addSubview(scroll)
        glass.contentView.addSubview(dismiss)
        formatViews = [scroll, dismiss]

        makeLinkRows()
        glass.contentView.addSubview(linkRows)

        let cancel = BarButton(image: Self.symbol("xmark"), title: String(localized: "Cancel"), handler: UIAction { [weak self] _ in
            self?.cancelLink()
        })
        // In the text's colour, as Cancel and every other symbol on the bar: the page's colour
        // there says a style is on.
        let done = BarButton(image: Self.symbol("checkmark"), title: String(localized: "Done"), handler: UIAction { [weak self] _ in
            self?.finishLink()
        })
        linkTitle.font = .preferredFont(forTextStyle: .headline)
        linkTitle.adjustsFontForContentSizeCategory = true
        linkTitle.textColor = .label
        linkTitle.textAlignment = .center
        linkTitle.accessibilityTraits = .header
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        for view in [cancel, linkTitle, done] {
            view.translatesAutoresizingMaskIntoConstraints = false
            buttonRow.addSubview(view)
        }
        glass.contentView.addSubview(buttonRow)


        // The row on the keys: the buttons, or a link's address. The glass grows up from it.
        let bottomRow = UILayoutGuide()
        glass.contentView.addLayoutGuide(bottomRow)
        glassHeight = glass.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        rowsHeightConstraint = linkRows.heightAnchor.constraint(equalToConstant: rowsHeight)

        fullWidthLeading = glass.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12)
        trailingHalfLeading = glass.leadingAnchor.constraint(equalTo: centerXAnchor)
        updateWidth()
        registerForTraitChanges([UITraitVerticalSizeClass.self]) { (bar: Self, _) in
            bar.updateWidth()
        }
        NSLayoutConstraint.activate([
            // Clear of the Dynamic Island and the rounded corners in landscape.
            glass.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            glassHeight,

            bottomRow.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            bottomRow.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            bottomRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),

            scroll.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: Self.edgeInset),
            scroll.topAnchor.constraint(equalTo: bottomRow.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor),

            dismiss.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -Self.edgeInset),
            dismiss.centerYAnchor.constraint(equalTo: bottomRow.centerYAnchor),
            sevenAcross,
            dismiss.widthAnchor.constraint(lessThanOrEqualToConstant: 60),
            dismiss.widthAnchor.constraint(greaterThanOrEqualToConstant: BarButton.width),
            firstSlot.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            firstSlot.widthAnchor.constraint(equalTo: dismiss.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(equalTo: dismiss.widthAnchor, multiplier: CGFloat(buttons.count)),

            // The rows where the buttons were and above, across the glass, growing up from the
            // keys as the address wraps.
            linkRows.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            linkRows.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            linkRows.bottomAnchor.constraint(equalTo: bottomRow.bottomAnchor),
            rowsHeightConstraint,
            nameIcon.centerXAnchor.constraint(equalTo: firstSlot.centerXAnchor),
            addressIcon.centerXAnchor.constraint(equalTo: firstSlot.centerXAnchor),
            linkText.leadingAnchor.constraint(equalTo: firstSlot.centerXAnchor, constant: 21),

            // Cancel over the rows' symbols, Done where the button putting the keys away is, and
            // what's being done between them.
            buttonRow.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: linkRows.topAnchor),
            buttonRow.heightAnchor.constraint(equalToConstant: Self.buttonRowHeight),
            cancel.centerXAnchor.constraint(equalTo: firstSlot.centerXAnchor),
            cancel.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            done.centerXAnchor.constraint(equalTo: dismiss.centerXAnchor),
            done.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            linkTitle.centerXAnchor.constraint(equalTo: buttonRow.centerXAnchor),
            linkTitle.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
            linkTitle.leadingAnchor.constraint(greaterThanOrEqualTo: cancel.trailingAnchor, constant: 8),
            linkTitle.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -8),
        ])
        showLinkRows(false, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// On a phone on its side the glass takes the trailing half, as Notes' toolbar does: the keys
    /// leave the page a few lines, and the lines' starts stay in view beside it, down to the keys.
    private var fullWidthLeading: NSLayoutConstraint!
    private var trailingHalfLeading: NSLayoutConstraint!

    private func updateWidth() {
        let isHalf = traitCollection.verticalSizeClass == .compact
        NSLayoutConstraint.deactivate([isHalf ? fullWidthLeading : trailingHalfLeading])
        NSLayoutConstraint.activate([isHalf ? trailingHalfLeading : fullWidthLeading])
    }

    /// Only the glass takes touches; the clear margin around it belongs to the text behind.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    /// Shows which styles are on where the editor's caret or selection is, so bold chosen for
    /// the next word shows before it's typed. Only styles show: turning one on changes nothing on
    /// the page until you type, while a line's kind shows on the page at once. The link button
    /// shows as on while the selection is a link's text, which it then takes the link off, as bold
    /// comes off bold text.
    func refresh() {
        let active = editor?.activeStyles ?? []
        let isLinkSelected = editor?.isLinkSelected ?? false
        for (action, button) in buttons {
            button.isOn = action == .link ? isLinkSelected : action.style.map(active.contains) ?? false
        }
        buttons[.link]?.isEnabled = editor?.canEditLink ?? false
        #if !SHARE_EXTENSION
        // An iPad's format panel, while it's out, which shows the same.
        FormatPanel.shared.refresh()
        #endif
    }

    #if DEBUG
    /// Whether the button for `action` shows as on. For tests.
    func showsOn(_ action: FormatAction) -> Bool {
        buttons[action]?.isOn ?? false
    }

    /// Whether the button for `action` can be pressed, rather than dimmed. For tests.
    func isEnabled(_ action: FormatAction) -> Bool {
        buttons[action]?.isEnabled ?? false
    }

    /// What the heading button's menu offers, as it would open now, top to bottom, and which it
    /// has ticked, its groups' items one after another. For tests.
    var headingMenuForTesting: [(title: String, isTicked: Bool)] {
        func items(_ menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { ($0 as? UIMenu).map(items) ?? [$0 as? UIAction].compactMap { $0 } }
        }
        return items(headingMenu()).map { ($0.title, $0.state == .on) }
    }

    /// How many groups the heading button's menu has, a line between each. For tests.
    var headingMenuGroupsForTesting: Int {
        headingMenu().children.count
    }

    /// As choosing `title` in the heading button's menu does. For tests.
    func chooseHeadingForTesting(_ title: String) {
        let kind = title == Self.plainText ? .paragraph : Self.headingLevels.first { $0.title == title }?.kind
        if let kind { editor?.setLineStyle(kind) }
    }

    /// Whether the heading button opens its menu out of the bar's glass. For tests.
    var headingMenuComesOutOfTheGlassForTesting: Bool {
        guard let button = buttons[.heading], let glassView else { return false }
        return button.showsMenuAsPrimaryAction && button.menuSource === glassView
    }

    /// The buttons along the bar, in order, and whether each shows whole. For tests.
    var buttonsAlongTheBar: [(action: FormatAction, isWhole: Bool)] {
        layoutIfNeeded()
        let shown = buttonScroll.map { CGRect(origin: $0.contentOffset, size: $0.bounds.size) } ?? .zero
        return buttons.filter { $0.key != .dismiss }
            .sorted { $0.value.frame.minX < $1.value.frame.minX }
            .map { ($0.key, shown.insetBy(dx: -0.5, dy: -0.5).contains($0.value.frame)) }
    }

    /// The distances between the middles of the buttons that show whole and the one putting the
    /// keys away, along the bar. For tests.
    var buttonGapsForTesting: [CGFloat] {
        layoutIfNeeded()
        guard let scroll = buttonScroll, let dismiss = buttons[.dismiss] else { return [] }
        let shown = CGRect(origin: scroll.contentOffset, size: scroll.bounds.size).insetBy(dx: -0.5, dy: -0.5)
        let middles = buttons.filter { $0.key != .dismiss && shown.contains($0.value.frame) }
            .map { $0.value.convert(CGPoint(x: $0.value.bounds.midX, y: 0), to: self).x }
            .sorted() + [dismiss.convert(CGPoint(x: dismiss.bounds.midX, y: 0), to: self).x]
        return zip(middles.dropFirst(), middles).map { $0 - $1 }
    }

    /// Scrolls the buttons to their end, as a finger would. For tests.
    func scrollButtonsToEnd() {
        guard let scroll = buttonScroll else { return }
        layoutIfNeeded()
        scroll.contentOffset.x = max(0, scroll.contentSize.width - scroll.bounds.width)
    }
    #endif

    /// The first six buttons, as the bar comes up with the keys (see `DotPager`): scrolled along
    /// before, it came back up showing where it was left.
    func showFirstButtons() {
        buttonScroll?.setContentOffset(.zero, animated: false)
    }

    private func makeButton(for action: FormatAction, fixedWidth: Bool = true) -> BarButton {
        let button = BarButton(image: Self.symbol(action.symbol), title: action.title, fixedWidth: fixedWidth, handler: UIAction { [weak self] _ in
            self?.editor?.perform(action)
        })
        // The heading button opens a menu of the heading levels instead, made as it opens, the
        // line's ticked. It comes out of the whole glass: the bar turns into the menu and back, as
        // Notes' keyboard toolbar does into its list styles.
        if action == .heading {
            button.makeMenu = { [weak self] in self?.headingMenu() ?? UIMenu() }
            button.menuSource = glassView
        }
        button.isLayered = action.hasOwnSymbol
        buttons[action] = button
        return button
    }

    /// The heading levels the heading button offers, one for each level the page shows, the line's
    /// ticked. Largest first.
    static let headingLevels: [(title: String, kind: BlockKind)] = [
        (String(localized: "Heading 1"), .heading1), (String(localized: "Heading 2"), .heading2), (String(localized: "Heading 3"), .heading3),
    ]
    /// What takes a line's heading off, offered only on a heading. A key of its own: other
    /// languages call the line's style and a link's text by different words.
    static let plainText = String(localized: "line-style.text", defaultValue: "Text")

    /// The heading levels, and on a heading, above them with a line between, plain text: as Notes'
    /// list styles menu has None only on a list.
    private func headingMenu() -> UIMenu {
        let current = editor?.lineStyle
        let levels = UIMenu(options: .displayInline, children: Self.headingLevels.map { title, kind in
            UIAction(title: title, state: current == kind ? .on : .off) { [weak self] _ in
                self?.editor?.setLineStyle(kind)
            }
        })
        guard let current, current != .paragraph else { return UIMenu(children: [levels]) }
        let text = UIMenu(options: .displayInline, children: [
            UIAction(title: Self.plainText) { [weak self] _ in self?.editor?.setLineStyle(.paragraph) },
        ])
        return UIMenu(children: [text, levels])
    }

    /// From the glass's ends to the first button and the last.
    private static let edgeInset: CGFloat = 10

    private static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium, scale: .large)

    private static func symbol(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: symbolConfiguration)
            ?? UIImage(named: name, in: nil, with: symbolConfiguration)
    }

    // MARK: Links

    /// The rows: a symbol for each where a button would be, the text view across both, what
    /// stands in for empty text in grey over it, and a line between the rows from where the text
    /// starts, as a list's lines are. The symbols and the line follow the rows' text as it wraps
    /// (`placeRows`).
    private func makeLinkRows() {
        linkRows.translatesAutoresizingMaskIntoConstraints = false
        for (icon, symbol) in [(nameIcon, "character.cursor.ibeam"), (addressIcon, "link")] {
            icon.image = Self.symbol(symbol)
            // In the text's colour, as the buttons are: the page's colour on the bar says a style
            // is on, and this only says what the row is.
            icon.tintColor = .label
            icon.contentMode = .center
            icon.isAccessibilityElement = false
            icon.translatesAutoresizingMaskIntoConstraints = false
            linkRows.addSubview(icon)
        }
        for label in [nameLabel, addressLabel] {
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .placeholderText
            label.lineBreakMode = .byTruncatingTail
            label.isAccessibilityElement = false
            label.translatesAutoresizingMaskIntoConstraints = false
            linkRows.addSubview(label)
        }
        divider.translatesAutoresizingMaskIntoConstraints = false
        linkRows.addSubview(divider)
        configureText()
        linkRows.addSubview(linkText)
        // A tap beside the text, on a row's symbol or in the gap under or over a row's text, is
        // the row's: the text gives a tap in the gap under an empty address's text row to the
        // address (TextKit 2, iOS 27), as far up as the text row's line.
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        tap.delegate = self
        linkRows.addGestureRecognizer(tap)
        linkRows.isInGap = { [unowned self] point in
            let y = linkRows.convert(point, to: linkText).y
            return y > nameLineBottom && y < addressLineTop
        }

        nameIconY = nameIcon.centerYAnchor.constraint(equalTo: linkText.topAnchor, constant: Self.rowHeight / 2)
        addressIconY = addressIcon.centerYAnchor.constraint(equalTo: linkText.topAnchor, constant: Self.rowHeight * 1.5)
        dividerY = divider.centerYAnchor.constraint(equalTo: linkText.topAnchor, constant: Self.rowHeight)
        NSLayoutConstraint.activate([
            linkText.trailingAnchor.constraint(equalTo: linkRows.trailingAnchor, constant: -18),
            linkText.topAnchor.constraint(equalTo: linkRows.topAnchor),
            linkText.bottomAnchor.constraint(equalTo: linkRows.bottomAnchor),
            nameIcon.widthAnchor.constraint(equalToConstant: 42),
            nameIcon.heightAnchor.constraint(equalToConstant: 44),
            nameIconY,
            addressIcon.widthAnchor.constraint(equalToConstant: 42),
            addressIcon.heightAnchor.constraint(equalToConstant: 44),
            addressIconY,
            nameLabel.leadingAnchor.constraint(equalTo: linkText.leadingAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: linkText.trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: nameIcon.centerYAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: linkText.leadingAnchor),
            addressLabel.trailingAnchor.constraint(lessThanOrEqualTo: linkText.trailingAnchor),
            addressLabel.centerYAnchor.constraint(equalTo: addressIcon.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: linkText.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: linkText.trailingAnchor),
            dividerY,
        ])
    }

    /// The text view is set up once, for both rows, and its keys never change: changed, they'd be
    /// rebuilt (see `linkText`). So the text is typed as an address is: nothing capitalised (a
    /// link's text is mostly mid-sentence anyway), corrected, predicted, checked or made curly.
    private func configureText() {
        linkText.delegate = self
        linkText.backgroundColor = .clear
        linkText.isScrollEnabled = false
        linkText.textContainer.lineFragmentPadding = 0
        linkText.textColor = .label
        linkText.accessibilityLabel = String(localized: "Link text and address")
        // The keys' own Return, as on the page, which the keys move over from: Done made it a tick.
        linkText.returnKeyType = .default
        linkText.keyboardType = .default
        linkText.autocapitalizationType = .none
        linkText.autocorrectionType = .no
        linkText.inlinePredictionType = .no
        linkText.spellCheckingType = .no
        linkText.smartQuotesType = .no
        linkText.smartDashesType = .no
        linkText.smartInsertDeleteType = .no
        linkText.translatesAutoresizingMaskIntoConstraints = false
        sizeText()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (bar: Self, _) in
            bar.sizeText()
            bar.setRows(name: bar.nameText, address: bar.addressText)
        }
    }

    /// Each row is a paragraph, its lines at the type size, with the space above and below a line
    /// that makes a row: half of it after each paragraph and half before, so a tap in the space
    /// goes to the row it's in, as far as the line between. A line wrapping on makes the row
    /// taller by its own height.
    private func sizeText() {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let lineHeight = ceil(font.lineHeight) + 2
        let padding = max(0, (Self.rowHeight - lineHeight) / 2)
        self.lineHeight = lineHeight
        linePadding = padding
        let style = NSMutableParagraphStyle()
        // TextKit adds the font's leading to a line's height as it's set here.
        style.minimumLineHeight = lineHeight - max(0, font.leading)
        style.maximumLineHeight = lineHeight - max(0, font.leading)
        style.paragraphSpacing = padding
        style.paragraphSpacingBefore = padding
        textAttributes = [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: style]
        linkText.textContainerInset = UIEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)
        linkText.font = font
    }

    /// Where the break between the rows is, in UTF-16.
    private var separator: Int {
        (linkText.text as NSString).range(of: "\n").location
    }

    /// The row the caret is on.
    private var keysRow: LinkRow {
        linkText.selectedRange.location <= separator ? .name : .address
    }

    /// Puts `name` and `address` in the rows, as one text.
    private func setRows(name: String, address: String) {
        nameText = name
        addressText = address
        linkText.attributedText = NSAttributedString(string: name + "\n" + address, attributes: textAttributes)
        rowsDidChange()
    }

    /// The rows as the text now says them, and the symbols, the line and the stand-ins, and the
    /// bar's height, to match: a row wrapping is taller.
    private func rowsDidChange() {
        let text = linkText.text ?? ""
        let separator = separator
        if separator == NSNotFound {
            // The break went, as it shouldn't (see `shouldChangeTextIn`): put back after what's typed.
            linkText.attributedText = NSAttributedString(string: text + "\n" + addressText, attributes: textAttributes)
            nameText = text
        } else {
            let whole = text as NSString
            nameText = whole.substring(to: separator)
            addressText = whole.substring(from: separator + 1)
        }
        linkText.typingAttributes = textAttributes
        nameLabel.text = namePlaceholder
        nameLabel.alpha = nameText.isEmpty ? 1 : 0
        addressLabel.text = String(localized: "Address")
        addressLabel.alpha = addressText.isEmpty ? 1 : 0
        placeRows()
    }

    /// The symbols beside their rows' first lines, the line between the rows, and the rows' height
    /// as the text wraps.
    private func placeRows() {
        linkText.layoutIfNeeded()
        // Asked how tall it is, the text is all laid out: asked where its end is alone, after a
        // change, it says where the end was.
        let width = linkText.bounds.width > 0 ? linkText.bounds.width : 300
        let fitsText = ceil(linkText.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let separator = separator
        guard separator != NSNotFound,
              let nameStart = linkText.position(from: linkText.beginningOfDocument, offset: 0),
              let nameEnd = linkText.position(from: linkText.beginningOfDocument, offset: separator),
              let addressStart = linkText.position(from: linkText.beginningOfDocument, offset: separator + 1) else { return }
        let first = linkText.caretRect(for: nameStart)
        let last = linkText.caretRect(for: nameEnd)
        let second = linkText.caretRect(for: addressStart)
        let end = linkText.caretRect(for: linkText.endOfDocument)
        nameIconY.constant = first.midY
        addressIconY.constant = second.midY
        dividerY.constant = (last.maxY + second.minY) / 2
        nameLineBottom = last.maxY
        addressLineTop = second.minY
        // Down to the last line's bottom and the space under it: what the text says it takes
        // leaves out an empty address's line.
        #if os(visionOS)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        #else
        let scale = window?.screen.scale ?? 3
        #endif
        let fitsLines = ((end.midY + lineHeight / 2 + linePadding) * scale).rounded() / scale
        let height = max(2 * Self.rowHeight, fitsText, fitsLines)
        guard abs(height - rowsHeight) > 0.5 else { return }
        rowsHeight = height
        rowsHeightConstraint.constant = height
        if showsLink {
            glassHeight.constant = Self.buttonRowHeight + rowsHeight
            onHeightChange?()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if showsLink { placeRows() }
    }

    private var namePlaceholder: String {
        address.isEmpty ? String(localized: "Text") : address
    }

    /// The link's text as it stands, nothing if it's blank: then it's the address.
    private var name: String {
        nameText.allSatisfy(\.isWhitespace) ? "" : nameText
    }

    private var address: String {
        addressText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The link as it stands in the bar, shown on the page as it's typed, lit, as Done would leave
    /// it. Not while an input method composes the text: its letters aren't the text yet.
    private func showLinkAsTyped() {
        guard let link = editingLink, let page = linkPage, linkText.markedTextRange == nil else { return }
        page.textView.showLinkTarget(page.previewLink(link, text: name, destination: address))
    }

    /// A tap on a row beside its text, on its symbol, brings the caret to the row's end; under or
    /// over the text, in the gap the rows meet in, to where it would go on the text's nearest
    /// line. A tap on the text is the text's: the caret goes where it's tapped.
    @objc private func rowTapped(_ tap: UITapGestureRecognizer) {
        tapRows(at: tap.location(in: linkRows))
    }

    private func tapRows(at point: CGPoint) {
        let row: LinkRow = point.y < divider.frame.midY ? .name : .address
        let inText = linkRows.convert(point, to: linkText)
        guard (linkText.bounds.minX...linkText.bounds.maxX).contains(inText.x) else { return moveKeys(to: row) }
        if !linkText.isFirstResponder { linkText.becomeFirstResponder() }
        let y = row == .name ? nameLineBottom - 1 : addressLineTop + 1
        guard let position = linkText.closestPosition(to: CGPoint(x: inText.x, y: y)) else { return moveKeys(to: row) }
        linkText.selectedTextRange = linkText.textRange(from: position, to: position)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view !== linkText
    }

    /// Moves the keys to `row`, the caret at the end of its text. The keys stay as they are, and
    /// the text too, which a field for each row couldn't give them (see `linkText`).
    private func moveKeys(to row: LinkRow) {
        if !linkText.isFirstResponder { linkText.becomeFirstResponder() }
        let separator = separator
        guard separator != NSNotFound else { return }
        linkText.selectedRange = NSRange(location: row == .name ? separator : (linkText.text as NSString).length, length: 0)
    }

    /// Shows `link` in the bar, its text above where it goes, to change, and moves the keys over
    /// to its address. They stay up, only changing to keys for an address. A drawer brought keys
    /// of its own: the page's went down first, and came back up only as the drawer went. Says
    /// whether it could, which takes a page that the bar is on.
    ///
    /// The page shows the link as it's typed. Done puts it there for good, as the keys' own
    /// Return does from the address; from the text, Return moves on to the address. Text left
    /// empty is the address, which stands in for it in grey and follows it as it's typed, and
    /// text that says its address comes up so; an address emptied takes the link off; a new link
    /// with no address is its text as text; both emptied is nothing, the link's text going; and
    /// both left as they were change nothing. Cancel puts the link back as it was. Anything else
    /// taking the keys, a tap on the page or on another link, another page or the keys put away,
    /// keeps it as typed, as Done does: it's on the page already.
    @discardableResult
    func editLink(_ link: EditorController.PageLink) -> Bool {
        guard let editor else { return false }
        // Tapped again while it's being changed, it keeps what's been typed.
        guard link != editingLink else { return true }
        var link = link
        if let current = editingLink, linkPage === editor {
            // Another link tapped: the one being changed is kept as typed first. The one tapped
            // stays as far from the page's end as it was, if it's after it.
            let storage = editor.textView.textStorage
            let fromEnd = storage.length - link.range.location
            applyLink()
            if link.range.location > current.range.location { link.range.location = storage.length - fromEnd }
        }
        linkTitle.text = link.isNew ? String(localized: "Add Link") : String(localized: "Edit Link")
        // Text that only says the address isn't typed: the address stands in for it, in grey,
        // which says so, and follows the address until text is typed. The rows are set before
        // the glass grows for them, to as tall as they stand.
        setRows(name: link.saysItsAddress ? "" : link.text, address: link.address)
        startEditing(link, on: editor)
        moveKeys(to: .address)
        return true
    }

    private func startEditing(_ link: EditorController.PageLink, on page: EditorController) {
        // The page keeps its room for the keys, which are only moving over to the link.
        if editingLink == nil { page.textView.keepKeyboardRoom() }
        linkPage?.textView.showLinkTarget(nil)
        editingLink = link
        linkPage = page
        isLinkSettled = false
        setLinkShown(true)
        // Once the page has made room for the taller bar, the link's text is lit above it.
        page.textView.showLinkTarget(link.range)
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        isEditingLink
    }

    /// Return in the text row moves on to the address, and in the address puts the link on the
    /// page. Neither row takes in the other, nor the break between them: lines pasted go in as
    /// one, with spaces between.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let separator = separator
        if text == "\n" {
            if range.location <= separator {
                moveKeys(to: .address)
            } else {
                finishLink()
            }
            return false
        }
        if separator != NSNotFound, range.location <= separator, NSMaxRange(range) > separator { return false }
        if text.contains(where: \.isNewline) {
            let joined = text.components(separatedBy: .newlines).joined(separator: " ")
            if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
               let end = textView.position(from: start, offset: range.length),
               let textRange = textView.textRange(from: start, to: end) {
                textView.replace(textRange, withText: joined)
                rowsDidChange()
                showLinkAsTyped()
            }
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        rowsDidChange()
        showLinkAsTyped()
    }

    /// A selection across the rows is no selection: it's the caret where it started. What's
    /// typed next keeps the rows' style wherever the caret goes: on an empty row, UIKit's own
    /// typing attributes would lay the row out with no space about it.
    func textViewDidChangeSelection(_ textView: UITextView) {
        textView.typingAttributes = textAttributes
        let selection = textView.selectedRange
        let separator = separator
        guard selection.length > 0, separator != NSNotFound, selection.location <= separator, NSMaxRange(selection) > separator else { return }
        textView.selectedRange = NSRange(location: selection.location, length: 0)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        textView.typingAttributes = textAttributes
    }

    /// The keys went elsewhere: to the page tapped or another page moved to, or away. The link
    /// is kept as typed, as Done keeps it.
    func textViewDidEndEditing(_ textView: UITextView) {
        applyLink()
        // A page taking the keys, as a tapped one does, doesn't have them yet: the bar lets the
        // link go once it has (`pageTookKeys`). With neither the page nor the link holding them,
        // the bar went down into the keys and came back up, and the page's room for it with it.
        guard !BiteTextView.isTakingKeys else { return }
        endLink()
    }

    /// A page has taken the keys from the link: the bar lets the link go, kept as typed or put
    /// back, the bar staying on the keys all along.
    func pageTookKeys() {
        guard isLinkSettled, !linkText.isFirstResponder else { return }
        endLink()
    }

    /// Puts the link's text and address on the page as they stand, as one edit, to undo all at
    /// once: what was shown as they were typed goes back first. Both left as they were change
    /// nothing, with nothing to undo.
    private func applyLink() {
        guard let link = editingLink, let page = linkPage, !isLinkSettled else { return }
        isLinkSettled = true
        page.textView.showLinkTarget(nil)
        page.endLinkPreview()
        page.setLink(link, text: name, destination: address)
    }

    /// Done: the link goes on the page as it stands, and the keys back to the page, as they are.
    /// The page has them before the bar lets the link go (`pageTookKeys`).
    private func finishLink() {
        let page = linkPage
        applyLink()
        page?.focus()
        endLink()
    }

    /// Cancel: the link goes back as it was, and the keys back to the page, the caret where it
    /// was.
    private func cancelLink() {
        let page = linkPage
        page?.textView.showLinkTarget(nil)
        page?.endLinkPreview()
        isLinkSettled = true
        page?.focus()
        endLink()
    }

    /// The bar goes back to its buttons, and what was shown as the link was typed, if it wasn't
    /// put on the page, goes back as it was.
    private func endLink() {
        guard editingLink != nil else { return }
        editingLink = nil
        linkPage?.textView.showLinkTarget(nil)
        linkPage?.endLinkPreview()
        linkPage = nil
        isLinkSettled = false
        setLinkShown(false)
        refresh()
    }

    /// Grows the glass up from the keys for a link, or back down to the buttons. The pager moves
    /// the bar and the page's room for it along (`onHeightChange`), in the same animation.
    private func setLinkShown(_ shown: Bool) {
        guard shown != showsLink else { return }
        showsLink = shown
        glassHeight.constant = shown ? Self.buttonRowHeight + rowsHeight : Self.rowHeight
        showLinkRows(shown, animated: window != nil)
        if let onHeightChange {
            onHeightChange()
        } else {
            layoutIfNeeded()
        }
    }

    /// The link's rows in place of the buttons, or the buttons back, fading over within the glass
    /// as it grows or shrinks. What goes fades out faster than what comes fades in: at the same
    /// pace, the two sets of symbols showed through each other halfway.
    private func showLinkRows(_ shows: Bool, animated: Bool) {
        let linkViews = [buttonRow, linkRows]
        for view in linkViews {
            view.isUserInteractionEnabled = shows
            view.accessibilityElementsHidden = !shows
        }
        for view in formatViews {
            view.isUserInteractionEnabled = !shows
            view.accessibilityElementsHidden = shows
        }
        let going = shows ? formatViews : linkViews
        let coming = shows ? linkViews : formatViews
        guard animated else {
            going.forEach { $0.alpha = 0 }
            coming.forEach { $0.alpha = 1 }
            return
        }
        let options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        UIView.animate(withDuration: 0.1, delay: 0, options: options) { going.forEach { $0.alpha = 0 } }
        UIView.animate(withDuration: 0.18, delay: 0.04, options: options) { coming.forEach { $0.alpha = 1 } }
    }

    #if DEBUG
    /// What the card says it's doing, over the link's rows.
    var linkTitleForTesting: String? { linkTitle.text }
    /// The rows' text as typed.
    var nameForTesting: String { nameText }
    var addressForTesting: String { addressText }
    /// What stands in for the link's text while none is typed.
    var namePlaceholderForTesting: String { namePlaceholder }
    var fieldForTesting: UITextView { linkText }
    /// The row the keys are on, while they're on the link.
    var rowWithKeysForTesting: LinkRow? { linkText.isFirstResponder ? keysRow : nil }
    var showsLinkForTesting: Bool { showsLink }
    /// How tall the rows stand.
    var rowsHeightForTesting: CGFloat { rowsHeight }
    /// Where the caret is in the rows' text, and where the text row ends in it.
    var caretForTesting: Int { linkText.selectedRange.location }
    var separatorForTesting: Int { separator }

    /// As pasting `text` where the caret is does.
    func pasteForTesting(_ text: String) {
        let range = linkText.selectedRange
        if textView(linkText, shouldChangeTextIn: range, replacementText: text) {
            linkText.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textAttributes))
            linkText.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
            textViewDidChange(linkText)
        }
    }

    /// As a tap on the link's text row does.
    func tapNameForTesting() {
        moveKeys(to: .name)
    }

    /// Where the rows' text starts, in their coordinates: 21 past the middle of their symbols.
    var linkTextLeadingForTesting: CGFloat {
        layoutIfNeeded()
        return linkText.frame.minX
    }

    /// As a tap at `point` on the rows does, in the rows' coordinates. Says whether the rows took
    /// it, rather than the text. Laid out first, as the bar is on screen before a finger can reach
    /// it: where the rows' lines are is measured as it lays out.
    @discardableResult
    func tapRowsForTesting(at point: CGPoint) -> Bool {
        setNeedsLayout()
        layoutIfNeeded()
        guard linkRows.hitTest(point, with: nil) === linkRows else { return false }
        tapRows(at: point)
        return true
    }

    /// As a tap on the link's address row does.
    func tapAddressForTesting() {
        moveKeys(to: .address)
    }

    /// As typing `text` in the link's text row does, the keys brought there first.
    func typeNameForTesting(_ text: String) {
        moveKeys(to: .name)
        setRows(name: text, address: addressText)
        moveKeys(to: .name)
        showLinkAsTyped()
    }

    /// As typing `text` in the link's address row does, the keys brought there first.
    func typeAddressForTesting(_ text: String) {
        moveKeys(to: .address)
        setRows(name: nameText, address: text)
        moveKeys(to: .address)
        showLinkAsTyped()
    }

    /// As Return in the link's text does.
    func returnNameForTesting() {
        moveKeys(to: .name)
        _ = textView(linkText, shouldChangeTextIn: NSRange(location: separator, length: 0), replacementText: "\n")
    }

    /// As Return in the link's address does.
    func returnLinkForTesting() {
        moveKeys(to: .address)
        _ = textView(linkText, shouldChangeTextIn: NSRange(location: (linkText.text as NSString).length, length: 0), replacementText: "\n")
    }

    /// As Cancel over the link does.
    func cancelLinkForTesting() {
        cancelLink()
    }

    /// As Done over the link does.
    func finishLinkForTesting() {
        finishLink()
    }

    /// As the keys going away from the link do, swiped down.
    func resignLinkForTesting() {
        linkText.resignFirstResponder()
    }

    /// Whether the button putting the keys away shows, to be pressed.
    var showsPutKeysAwayForTesting: Bool {
        guard let button = buttons[.dismiss] else { return false }
        return button.alpha > 0 && button.isUserInteractionEnabled && !button.accessibilityElementsHidden
    }

    /// Where the glass is in the bar.
    var glassFrameForTesting: CGRect {
        subviews.first { $0 is UIVisualEffectView }?.frame ?? .zero
    }
    #endif
}

/// A link's rows: a touch in the gap between a row's text and the line between the rows is the
/// rows' to place (see `FormatBar.tapRows`), not the text's, which would give it to the other row.
private final class LinkRowsView: UIView {
    var isInGap: (CGPoint) -> Bool = { _ in false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view != nil && isInGap(point) ? self : view
    }
}

/// A line a pixel thick on any screen, in the colour of a list's dividers.
private final class Hairline: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .separator
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: Hairline, _) in
            view.invalidateIntrinsicContentSize()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 1 / max(1, traitCollection.displayScale))
    }
}

/// The buttons fade out toward an edge with more of them beyond it, so a button cut off there,
/// lit or not, reads as the first of more rather than as a broken shape.
private final class FadingScrollView: UIScrollView {
    private let fade = CAGradientLayer()
    private let fadeWidth: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer.mask = fade
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Runs on every step of a scroll. Each fade grows with how much is hidden past its edge, so
    /// it comes in as the buttons start to move rather than all at once.
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(bounds.width, 1)
        let hiddenBefore = min(max(contentOffset.x, 0) / fadeWidth, 1)
        let hiddenAfter = min(max(contentSize.width - contentOffset.x - width, 0) / fadeWidth, 1)
        let edge = NSNumber(value: min(fadeWidth / width, 0.5))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        fade.colors = [UIColor(white: 0, alpha: 1 - hiddenBefore), .black, .black, UIColor(white: 0, alpha: 1 - hiddenAfter)].map(\.cgColor)
        CATransaction.commit()
    }
}

/// A bar button: just its symbol, which takes the page's colour, the bar's tint, while it's on,
/// and dims while pressed. Both change on the spot. A system button's configuration put a platter
/// behind the symbol when pressed and faded it out after, so a style's colour seemed to lag behind
/// the tap: it has none, and draws its symbol itself. A button still, not a plain control: only a
/// button's menu comes out of its glass, the bar turning into the menu (see `menuSource`); a
/// control's opened over the bar, the bar left as it was.
private final class BarButton: UIButton {
    /// The width of a button on its own; along the bar they share its width, six across.
    static let width: CGFloat = 42

    /// A menu a tap opens in place of the button's action, made as it opens.
    var makeMenu: (() -> UIMenu)? {
        didSet {
            isContextMenuInteractionEnabled = makeMenu != nil
            showsMenuAsPrimaryAction = makeMenu != nil
        }
    }

    /// What the menu comes out of and goes back into: the system turns this view into the menu.
    weak var menuSource: UIView?

    private let symbol = UIImageView()

    /// Drawn in layers, as Bite's own quote symbol is: the block a lighter shade of the bar's
    /// colour, as Notes draws its own.
    var isLayered = false {
        didSet { updateLook() }
    }

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            accessibilityTraits = isOn ? [.button, .selected] : .button
            updateLook()
        }
    }

    init(image: UIImage?, title: String, fixedWidth: Bool = true, handler: UIAction) {
        super.init(frame: .zero)
        symbol.image = image
        symbol.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        NSLayoutConstraint.activate([
            symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 44),
        ])
        if fixedWidth {
            widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        }
        addAction(handler, for: .touchUpInside)
        // A pointer, as an iPad's trackpad's, lights the button it's over, taking its shape.
        isPointerInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
        updateLook()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue { updateLook() }
        }
    }

    override var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue { updateLook() }
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateLook()
    }

    override func accessibilityActivate() -> Bool {
        // With a menu, the system opens it.
        if makeMenu != nil { return false }
        sendActions(for: .touchUpInside)
        return true
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let makeMenu else { return nil }
        let configuration = UIContextMenuConfiguration(actionProvider: { _ in makeMenu() })
        configuration.preferredMenuElementOrder = .fixed
        return configuration
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let source = menuSource, source.window != nil else { return nil }
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(roundedRect: source.bounds, cornerRadius: min(source.bounds.height, source.bounds.width) / 2)
        return UITargetedPreview(view: source, parameters: parameters)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        contextMenuInteraction(interaction, previewForHighlightingMenuWithConfiguration: configuration)
    }

    private func updateLook() {
        symbol.tintColor = isOn ? tintColor : .label
        symbol.preferredSymbolConfiguration = isLayered ? UIImage.SymbolConfiguration(hierarchicalColor: isOn ? tintColor : .label) : nil
        symbol.alpha = !isEnabled ? 0.25 : isHighlighted ? 0.35 : 1
    }
}
