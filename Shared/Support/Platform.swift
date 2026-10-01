#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// The editor's code is the same on iPhone and Mac. What differs between UIKit and AppKit is
// named here once.

#if canImport(UIKit)
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#else
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

nonisolated extension PlatformColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// One colour in light appearance and another in dark, chosen each time it's drawn.
    static func adaptive(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
        #else
        NSColor(name: nil) { appearance in appearance.isDark ? dark : light }
        #endif
    }

    /// `color` with `alpha` in light appearance and `darkAlpha` in dark, for a colour that is
    /// itself different in each.
    static func adaptive(_ color: PlatformColor, alpha: CGFloat, darkAlpha: CGFloat) -> PlatformColor {
        #if canImport(UIKit)
        UIColor { traits in
            color.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? darkAlpha : alpha)
        }
        #else
        NSColor(name: nil) { appearance in
            var resolved = color
            appearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB) ?? color
            }
            return resolved.withAlphaComponent(appearance.isDark ? darkAlpha : alpha)
        }
        #endif
    }

    static var primaryText: PlatformColor {
        #if canImport(UIKit)
        .label
        #else
        .labelColor
        #endif
    }

    static var secondaryText: PlatformColor {
        #if canImport(UIKit)
        .secondaryLabel
        #else
        .secondaryLabelColor
        #endif
    }

    static var separatorLine: PlatformColor {
        #if canImport(UIKit)
        .separator
        #else
        .separatorColor
        #endif
    }
}

#if canImport(AppKit) && !canImport(UIKit)
nonisolated extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
#endif

nonisolated extension PlatformFont {
    /// The same font in bold, italic or both.
    func adding(bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(UIKit)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard traits != fontDescriptor.symbolicTraits, let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #else
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard traits != fontDescriptor.symbolicTraits else { return self }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
        #endif
    }

    func resized(to size: CGFloat) -> PlatformFont {
        #if canImport(UIKit)
        withSize(size)
        #else
        NSFont(descriptor: fontDescriptor, size: size) ?? self
        #endif
    }
}

/// The general pasteboard. Bite's own copies carry their Markdown under a type of their own as
/// well, so they paste back exactly.
enum Clipboard {
    static let markdownType = "com.chenyeni.bite.markdown"

    /// The general pasteboard, or a private one, so tests leave the person's own alone.
    #if canImport(UIKit)
    static var board = UIPasteboard.general
    #else
    static var board = NSPasteboard.general
    #endif

    static var string: String? {
        get {
            #if canImport(UIKit)
            board.string
            #else
            board.string(forType: .string)
            #endif
        }
        set {
            #if canImport(UIKit)
            board.string = newValue
            #else
            board.clearContents()
            if let newValue { board.setString(newValue, forType: .string) }
            #endif
        }
    }

    /// The Markdown of a copy made in Bite, while the pasteboard still holds it.
    static var markdown: String? {
        #if canImport(UIKit)
        board.data(forPasteboardType: markdownType).flatMap { String(data: $0, encoding: .utf8) }
        #else
        board.data(forType: NSPasteboard.PasteboardType(markdownType)).flatMap { String(data: $0, encoding: .utf8) }
        #endif
    }

    /// `text` for other apps, with its Markdown for Bite.
    static func set(_ text: String, markdown: String) {
        #if canImport(UIKit)
        board.items = [[
            "public.utf8-plain-text": text,
            markdownType: Data(markdown.utf8),
        ]]
        #else
        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(markdown.utf8), forType: NSPasteboard.PasteboardType(markdownType))
        #endif
    }
}
