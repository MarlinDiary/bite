import SwiftUI
import UIKit
import BiteKit

nonisolated extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

}

/// How strongly each page is washed with its dot's colour.
nonisolated enum PageTint {
    static func opacity(dark: Bool) -> CGFloat {
        dark ? 0.09 : 0.08
    }
}

nonisolated extension DotColor {
    var uiColor: UIColor {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        return UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : lightColor }
    }

    var color: Color {
        Color(uiColor: uiColor)
    }

    /// The colour made lighter or darker by `delta` in OKLab, for light and dark appearance.
    func shade(_ delta: Double) -> Color {
        let lightColor = UIColor(hex: ColorMath.adjustingLightness(light, by: delta))
        let darkColor = UIColor(hex: ColorMath.adjustingLightness(dark, by: delta))
        return Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}
