import SwiftUI
import UIKit

/// A bar button of the system's own, alone in a toolbar of its own, for an iPad's Aa and "…": the
/// pointer lights it as it does a toolbar's, and its popover or menu grows out of it with no
/// arrow, as from Notes' toolbar (iOS 26). Drawn by SwiftUI's or UIKit's glass buttons, the
/// pointer left the "…" button unlit, and a popover stood beside Aa pointing at it (user,
/// 2026-10-08).
struct SystemBarButton: UIViewRepresentable {
    enum Edge {
        case leading, trailing
    }

    let symbol: String
    let title: LocalizedStringResource
    /// The end of the dot bar it stands at, its edge on this view's.
    let edge: Edge
    /// The symbol's colour: the page's, as the dot bar's.
    let tint: UIColor
    /// What a tap does, given the button to come out of. Without, the button opens `menu`.
    var action: ((UIBarButtonItem) -> Void)?
    /// The menu, made each time it opens.
    var menu: (() -> [UIMenuElement])?

    func makeUIView(context: Context) -> SystemBarButtonView {
        SystemBarButtonView(symbol: symbol, title: String(localized: title), edge: edge, coordinator: context.coordinator)
    }

    func updateUIView(_ view: SystemBarButtonView, context: Context) {
        context.coordinator.action = action
        context.coordinator.menu = menu
        view.item.tintColor = tint
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, menu: menu)
    }

    final class Coordinator {
        var action: ((UIBarButtonItem) -> Void)?
        var menu: (() -> [UIMenuElement])?

        init(action: ((UIBarButtonItem) -> Void)?, menu: (() -> [UIMenuElement])?) {
            self.action = action
            self.menu = menu
        }
    }
}

/// The toolbar holding the button. A toolbar puts its buttons 20 points in from its ends on an
/// iPad: it's 20 points wider on each side, so the button's edge meets this view's. The toolbar
/// draws its buttons with SwiftUI inside (iOS 26), with no view of UIKit's to measure.
///
/// In a window that isn't full screen, the toolbar moves a button at the window's start along,
/// clear of the window's controls, past this view: Aa stood 51 points along from its place there,
/// where no touch reached it (user, 2026-10-09). The button says where it is (`buttonFrame(in:)`)
/// and touches there are taken to it (`buttonView(at:with:)`). The toolbar's left as it is: made
/// wider to reach the button, it moved the button further along.
final class SystemBarButtonView: UIView {
    let item = UIBarButtonItem()
    private let toolbar = UIToolbar()
    private static let toolbarInset: CGFloat = 20

    init(symbol: String, title: String, edge: SystemBarButton.Edge, coordinator: SystemBarButton.Coordinator) {
        super.init(frame: .zero)
        // As the "…" button drew its own.
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        if coordinator.menu != nil {
            item.image = image
            item.menu = UIMenu(children: [UIDeferredMenuElement.uncached { completion in
                completion(coordinator.menu?() ?? [])
            }])
            // Top to bottom as written, the bar being at the top.
            item.preferredMenuElementOrder = .fixed
        } else {
            item.primaryAction = UIAction(title: title, image: image) { [weak self] _ in
                guard let self else { return }
                coordinator.action?(self.item)
            }
        }
        item.accessibilityLabel = title
        toolbar.items = edge == .leading ? [item, .flexibleSpace()] : [.flexibleSpace(), item]
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        toolbar.frame = bounds.insetBy(dx: -Self.toolbarInset, dy: 0)
    }

    /// The button's round, as big as this view, in `view`'s space: where the toolbar has put it.
    func buttonFrame(in view: UIView) -> CGRect? {
        guard let frame = item.frame(in: self) else { return nil }
        let round = CGRect(x: frame.midX - bounds.width / 2, y: frame.midY - bounds.height / 2,
                           width: bounds.width, height: bounds.height)
        return convert(round, to: view)
    }

    /// What takes a touch on the button's round at `point`, in this view's space. The toolbar draws
    /// the button where the system has moved it, past the toolbar's own bounds, where its
    /// hit-testing stops: it's left to the outermost of the toolbar's views that has the point
    /// and takes it. The round's rim takes a touch as the button inside it does.
    func buttonView(at point: CGPoint, with event: UIEvent?) -> UIView? {
        var point = point
        if let button = item.frame(in: self)?.insetBy(dx: 1, dy: 1) {
            point = CGPoint(x: min(max(point.x, button.minX), button.maxX), y: min(max(point.y, button.minY), button.maxY))
        }
        func hit(at point: CGPoint, in container: UIView) -> UIView? {
            if container.point(inside: point, with: event), let view = container.hitTest(point, with: event) { return view }
            for subview in container.subviews.reversed() where !subview.isHidden && subview.isUserInteractionEnabled {
                if let view = hit(at: container.convert(point, to: subview), in: subview) { return view }
            }
            return nil
        }
        return hit(at: convert(point, to: toolbar), in: toolbar)
    }
}
