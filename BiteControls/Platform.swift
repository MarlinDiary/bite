import SwiftUI
#if canImport(UIKit)
import UIKit

typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit

typealias PlatformFont = NSFont
typealias PlatformColor = NSColor

nonisolated extension NSFont {
    /// A row of text in the font, as UIKit's `lineHeight` gives it.
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
#endif

nonisolated extension PlatformColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// `light` in light appearance and `dark` in dark, as the widget is shown.
    static func adaptive(light: UInt32, dark: UInt32) -> PlatformColor {
        #if canImport(UIKit)
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
        #else
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) }
        #endif
    }
}

extension Color {
    init(platform color: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: color)
        #else
        self.init(nsColor: color)
        #endif
    }

    /// The system's colours for text, for quieter text, and for a rule between things.
    static var systemLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color(nsColor: .labelColor)
        #endif
    }

    static var systemSecondaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color(nsColor: .secondaryLabelColor)
        #endif
    }

    static var systemSeparator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}
