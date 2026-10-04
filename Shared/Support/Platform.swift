#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import BiteKit

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

    /// What a paste brings: the Markdown of a copy made in Bite, or the text, with any links it
    /// had as rich text, from a web page or another app, written in as Markdown. As plain text
    /// alone the links went, and only their words came.
    static var textToPaste: String? {
        if let markdown { return markdown }
        guard let string else { return nil }
        let links = copiedLinks
        guard !links.isEmpty else { return string }
        return MarkdownSerializer.markdown(of: string.replacingOccurrences(of: "\u{A0}", with: " "), links: links)
    }

    /// The links in what was copied as rich text, in order.
    private static var copiedLinks: [MarkdownSerializer.CopiedLink] {
        guard let rich = richText else { return [] }
        let whole = rich.string.replacingOccurrences(of: "\u{A0}", with: " ") as NSString
        var links: [MarkdownSerializer.CopiedLink] = []
        rich.enumerateAttribute(.link, in: NSRange(location: 0, length: rich.length)) { value, range, _ in
            guard let destination = (value as? URL)?.absoluteString ?? value as? String, !destination.isEmpty else { return }
            let text = whole.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            // A link in Bite is on one line.
            guard !text.isEmpty, !text.contains("\n") else { return }
            let occurrence = whole.substring(to: range.location).components(separatedBy: text).count - 1
            links.append((text, destination, occurrence))
        }
        return links
    }

    /// What was copied as rich text, read from the first kind there is: HTML last, as WebKit reads
    /// it, which takes longest. Very long copies are left as plain text, so a paste doesn't hang.
    private static var richText: NSAttributedString? {
        let kinds: [(type: String, document: NSAttributedString.DocumentType)] = [
            ("public.rtf", .rtf), ("com.apple.flat-rtfd", .rtfd), ("public.html", .html),
        ]
        for kind in kinds {
            #if canImport(UIKit)
            guard let data = board.data(forPasteboardType: kind.type) else { continue }
            #else
            guard let data = board.data(forType: NSPasteboard.PasteboardType(kind.type)) else { continue }
            #endif
            guard data.count < 2_000_000 else { return nil }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: kind.document]
            if kind.document == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue }
            if let text = try? NSAttributedString(data: data, options: options, documentAttributes: nil) { return text }
        }
        return nil
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
