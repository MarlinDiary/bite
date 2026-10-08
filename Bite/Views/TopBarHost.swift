import SwiftUI
import UIKit

/// Moves the dot bar up out of the way of the keys and back, with them. The bar is in a view of
/// UIKit's for this (see `TopBarHost`), so the move is Core Animation's, in the keys' own
/// animation, as the format bar's is. Moved by SwiftUI, the bar was gone in one frame as the keys
/// came up on the phone: SwiftUI animates a frame at a time on the main thread, which the keys
/// coming up hold for a moment there.
@MainActor
final class TopBarMover {
    fileprivate weak var view: UIView?
    /// How far up the bar goes, out of sight.
    fileprivate var lift: CGFloat = 0
    private(set) var isAway = false

    /// Called inside the keys' animation, which then carries the move.
    func move(away: Bool) {
        isAway = away
        guard let view else { return }
        view.alpha = away ? 0 : 1
        view.transform = away ? CGAffineTransform(translationX: 0, y: -lift) : .identity
    }

    #if DEBUG
    func attachForTesting(_ view: UIView, lift: CGFloat) {
        self.view = view
        self.lift = lift
    }
    #endif
}

/// The dot bar and the "…" button in a view controller of their own, which `TopBarMover` moves.
struct TopBarHost<Content: View>: UIViewControllerRepresentable {
    let mover: TopBarMover
    let lift: CGFloat
    let content: Content

    func makeUIViewController(context: Context) -> TopBarController<Content> {
        let controller = TopBarController(content: content)
        mover.view = controller.host.view
        mover.lift = lift
        UIView.performWithoutAnimation { mover.move(away: mover.isAway) }
        return controller
    }

    func updateUIViewController(_ controller: TopBarController<Content>, context: Context) {
        controller.host.rootView = content
        mover.lift = lift
    }
}

final class TopBarController<Content: View>: UIViewController {
    let host: UIHostingController<Content>

    init(content: Content) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = TopBarView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Put where SwiftUI puts this, which allowed for the safe area already.
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// Takes touches only on the bar's own controls, the dots' capsule in the middle and the "…"
/// button at the end, on an iPad the Aa button at the start too, and in the share extension its
/// buttons at either end. Elsewhere along it they go to the page behind, as they did with the bar
/// in SwiftUI.
private final class TopBarView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        #if !SHARE_EXTENSION
        // An iPad's Aa and "…", where their toolbars have them. Left out, Aa took no touches:
        // they went to the page under it (user, 2026-10-08). In a window that isn't full screen,
        // Aa stands well along from its own place, past the window's controls, and it took none
        // there (2026-10-09).
        for button in barButtons(in: self) {
            if let round = button.buttonFrame(in: self), round.contains(point) {
                return button.buttonView(at: convert(point, to: button), with: event)
            }
        }
        #endif
        let height = DotSwitcher.height
        let capsule = CGRect(x: bounds.midX - DotSwitcher.width / 2, y: 0, width: DotSwitcher.width, height: height)
        let menu = CGRect(x: bounds.maxX - height, y: 0, width: height, height: height)
        #if SHARE_EXTENSION
        let start = CGRect(x: 0, y: 0, width: height, height: height)
        #else
        let start = CGRect.null
        #endif
        guard capsule.contains(point) || menu.contains(point) || start.contains(point) else { return nil }
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    #if !SHARE_EXTENSION
    private func barButtons(in view: UIView) -> [SystemBarButtonView] {
        view.subviews.flatMap { subview in
            (subview as? SystemBarButtonView).map { [$0] } ?? barButtons(in: subview)
        }
    }
    #endif
}
