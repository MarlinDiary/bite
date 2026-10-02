import UIKit
import BiteKit

/// Formatting buttons above the keyboard. All seven editors share one bar, so it stays put
/// when you swipe to another dot while typing. The pager places it on top of the keys.
final class FormatBar: UIView {
    static let shared = FormatBar()
    /// The glass capsule and the space around it, down to the top of the keys.
    static let height: CGFloat = 60
    weak var editor: EditorController?
    private var buttons: [FormatAction: FormatButton] = [:]

    private init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: Self.height))
        backgroundColor = .clear

        // Interactive, as the dot bar is: the glass swells under a finger and springs back.
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        let glass = UIVisualEffectView(effect: effect)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerConfiguration = .capsule()
        addSubview(glass)

        let scroll = FadingScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let buttons = FormatAction.allCases.filter { $0 != .dismiss }.map { makeButton(for: $0) }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let dismiss = makeButton(for: .dismiss)
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(scroll)
        glass.contentView.addSubview(dismiss)

        NSLayoutConstraint.activate([
            // Clear of the Dynamic Island and the rounded corners in landscape.
            glass.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            glass.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            glass.heightAnchor.constraint(equalToConstant: 48),

            scroll.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor),

            dismiss.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -6),
            dismiss.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Only the capsule takes touches; the clear margin around it belongs to the text behind.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    /// Shows which styles are on where the editor's caret or selection is, so bold chosen for
    /// the next word shows before it's typed. Only styles show: turning one on changes nothing on
    /// the page until you type, while a line's kind shows on the page at once.
    func refresh() {
        let active = editor?.activeStyles ?? []
        for (action, button) in buttons {
            button.isOn = action.style.map(active.contains) ?? false
        }
    }

    #if DEBUG
    /// Whether the button for `action` shows as on. For tests.
    func showsOn(_ action: FormatAction) -> Bool {
        buttons[action]?.isOn ?? false
    }
    #endif

    private func makeButton(for action: FormatAction) -> FormatButton {
        let button = FormatButton(action: action, handler: UIAction { [weak self] _ in
            self?.editor?.perform(action)
        })
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        buttons[action] = button
        return button
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

/// A format bar button: just its symbol, which takes the page's colour, the bar's tint, while
/// its style is on, and dims while pressed. Both change on the spot. A system button put a
/// platter behind the symbol when pressed and faded it out after, so a style's colour seemed
/// to lag behind the tap.
private final class FormatButton: UIControl {
    private let symbol = UIImageView()

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            accessibilityTraits = isOn ? [.button, .selected] : .button
            updateLook()
        }
    }

    init(action: FormatAction, handler: UIAction) {
        super.init(frame: .zero)
        symbol.image = UIImage(
            systemName: action.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium, scale: .large)
        )
        symbol.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        NSLayoutConstraint.activate([
            symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addAction(handler, for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = action.title
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

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateLook()
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }

    private func updateLook() {
        symbol.tintColor = isOn ? tintColor : .label
        symbol.alpha = isHighlighted ? 0.35 : 1
    }
}
