import UIKit

/// The system's share sheet, for a page as text or as a file (see `DotMenu`).
enum ShareSheet {
    static func present(text: String, in window: UIWindow? = nil) {
        present(items: [text], in: window)
    }

    /// In `window`, the one the menu was opened in, of Bite's several on an iPad; or else the one
    /// in front. Each of them says it's its scene's key window.
    static func present(items: [Any], in window: UIWindow? = nil) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.compactMap(\.keyWindow)
        guard let window = window ?? windows.first(where: \.isKeyWindow) ?? scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 40, y: top.view.safeAreaInsets.top + 22, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }
}
