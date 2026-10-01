import SwiftUI
import BiteKit

/// How strongly each page is washed with its dot's colour.
nonisolated enum PageTint {
    static func opacity(dark: Bool) -> CGFloat {
        dark ? 0.09 : 0.08
    }

    /// On the Mac's glass panel, a little paler than on a page: stronger, it went muddy over the
    /// frost.
    static func glassOpacity(dark: Bool) -> CGFloat {
        dark ? 0.09 : 0.07
    }

    /// How much of the page's own background lies over the Mac's glass, which made it thicker.
    static let glassFrost: CGFloat = 0.4
}

nonisolated extension DotColor {
    var platformColor: PlatformColor {
        .adaptive(light: PlatformColor(hex: light), dark: PlatformColor(hex: dark))
    }

    var color: Color {
        Color(platform: platformColor)
    }

    /// The colour made lighter or darker by `delta` in OKLab, for light and dark appearance.
    func shade(_ delta: Double) -> Color {
        Color(platform: .adaptive(light: PlatformColor(hex: ColorMath.adjustingLightness(light, by: delta)),
                                  dark: PlatformColor(hex: ColorMath.adjustingLightness(dark, by: delta))))
    }
}

nonisolated private extension Color {
    init(platform color: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: color)
        #else
        self.init(nsColor: color)
        #endif
    }
}
