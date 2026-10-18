#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import BiteKit

nonisolated extension NSAttributedString.Key {
    /// `BlockKind.rawValue` of the line a character belongs to.
    static let biteBlock = NSAttributedString.Key("bite.block")
    /// List nesting level (Int).
    static let biteIndent = NSAttributedString.Key("bite.indent")
    /// Whether a to-do is done (Bool).
    static let biteChecked = NSAttributedString.Key("bite.checked")
    /// `InlineStyle.rawValue` (Int).
    static let biteInline = NSAttributedString.Key("bite.inline")
    /// Where a link's text goes, as the Markdown has it (String).
    static let biteLink = NSAttributedString.Key("bite.link")
    /// Derived: an address written out in the text, which shows as a link (String, the address).
    static let biteWrittenLink = NSAttributedString.Key("bite.writtenLink")
    /// Derived: the number shown in front of an ordered item (Int).
    static let biteOrdinal = NSAttributedString.Key("bite.ordinal")
    /// Derived: `RunPosition.rawValue` (Int).
    static let biteRunPosition = NSAttributedString.Key("bite.runPosition")
    /// Derived: `BlockKind.rawValue` of the line above, which decides the room above this one
    /// (String, empty on the page's first line).
    static let biteKindAbove = NSAttributedString.Key("bite.kindAbove")
    /// The number written on an ordered item, where a list starts (Int, -1 for none).
    static let biteNumber = NSAttributedString.Key("bite.number")
    /// The language named on a code block's fence (String, empty for none).
    static let biteLanguage = NSAttributedString.Key("bite.language")
    /// `NumberStyle.rawValue` written on an ordered item, where a list starts (String, empty for none).
    static let biteNumberStyle = NSAttributedString.Key("bite.numberStyle")
    /// Derived: `NumberStyle.rawValue` an ordered item is shown in, its list's (String, empty for none).
    static let biteShownStyle = NSAttributedString.Key("bite.shownStyle")
}

/// A line's block attributes. They sit on every character of the line, newline included,
/// so an empty line still knows what it is.
nonisolated struct BlockAttributes: Equatable, Sendable {
    var kind: BlockKind = .paragraph
    var indent = 0
    var isChecked = false
    /// As in `Block`. A number stays on its line when the line stops starting a list, where it
    /// has no effect, so it's back if the line starts one again.
    var number: Int?
    /// As in `Block`, and kept like `number`.
    var numberStyle: NumberStyle?
    var language = ""

    init(kind: BlockKind = .paragraph, indent: Int = 0, isChecked: Bool = false, number: Int? = nil,
         numberStyle: NumberStyle? = nil, language: String = "") {
        self.kind = kind
        self.indent = indent
        self.isChecked = isChecked
        self.number = number
        self.numberStyle = numberStyle
        self.language = language
    }

    init(_ attributes: [NSAttributedString.Key: Any]) {
        kind = (attributes[.biteBlock] as? String).flatMap(BlockKind.init(rawValue:)) ?? .paragraph
        indent = attributes[.biteIndent] as? Int ?? 0
        isChecked = attributes[.biteChecked] as? Bool ?? false
        number = (attributes[.biteNumber] as? Int).flatMap { $0 >= 0 ? $0 : nil }
        numberStyle = (attributes[.biteNumberStyle] as? String).flatMap(NumberStyle.init(rawValue:))
        language = attributes[.biteLanguage] as? String ?? ""
    }

    init(_ block: Block) {
        self.init(kind: block.kind, indent: block.indent, isChecked: block.isChecked, number: block.number,
                  numberStyle: block.numberStyle, language: block.language)
    }

    /// Every key every time, so laying it over a line replaces whatever the line had.
    var dictionary: [NSAttributedString.Key: Any] {
        [.biteBlock: kind.rawValue, .biteIndent: indent, .biteChecked: isChecked, .biteNumber: number ?? -1,
         .biteNumberStyle: numberStyle?.rawValue ?? "", .biteLanguage: language]
    }
}

/// Where a code or quote line sits among the lines of its kind around it: it decides a code
/// block's rounded corners, and where a quote's bar starts and stops.
nonisolated enum RunPosition: Int, Sendable {
    case single, first, middle, last

    var isFirst: Bool { self == .single || self == .first }
    var isLast: Bool { self == .single || self == .last }
}

/// Fonts, colours and spacing for the editor. Display attributes are always derived from the
/// block and inline attributes through here, never stored on their own.
nonisolated struct EditorTheme: @unchecked Sendable {
    /// Every size here is a phone's, times this. A Mac's point is larger on screen than a phone's,
    /// so the same text is set smaller there.
    #if os(macOS)
    static let scale: CGFloat = 15.0 / 17.0
    #else
    static let scale: CGFloat = 1
    #endif

    let accent: PlatformColor
    let bodyFont = PlatformFont.systemFont(ofSize: 17 * Self.scale)
    let heading1Font = PlatformFont.systemFont(ofSize: 28 * Self.scale, weight: .bold)
    let heading2Font = PlatformFont.systemFont(ofSize: 22 * Self.scale, weight: .bold)
    let heading3Font = PlatformFont.systemFont(ofSize: 19 * Self.scale, weight: .semibold)
    let codeFont = PlatformFont.monospacedSystemFont(ofSize: 14.5 * Self.scale, weight: .regular)
    let numberFont = PlatformFont.monospacedDigitSystemFont(ofSize: 16 * Self.scale, weight: .semibold)

    /// Room between a list line's indent and its text, where the marker is drawn.
    let markerWidth: CGFloat = 28 * Self.scale
    let indentStep: CGFloat = 24 * Self.scale
    let quoteIndent: CGFloat = 18 * Self.scale
    let codeInset: CGFloat = 14 * Self.scale
    let codePadding: CGFloat = 9 * Self.scale

    private var scale: CGFloat { Self.scale }

    init(accent: PlatformColor) {
        self.accent = accent
    }

    /// A deeper shade of the page's own wash, where a neutral grey looked like a dull film over
    /// the coloured pages. See-through, over the wash.
    var codeBackground: PlatformColor {
        .adaptive(accent, alpha: 0.09, darkAlpha: 0.10)
    }

    /// The slant given to italic text in scripts whose fonts have no italic, close to the angle
    /// of the system font's italic.
    static let italicSlant: CGFloat = 0.2

    /// Han, kana, Hangul and full-width forms, which the system's fonts can't set in italic.
    static func lacksItalics(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FDF, 0x3000...0x30FF, 0x3100...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFFEF, 0x20000...0x3134F:
            true
        default:
            false
        }
    }

    /// The deepest list level that indents further. Deeper items, which only come from pasted or
    /// opened Markdown, line up with it, so the text keeps room on a phone.
    static let deepestIndent = 6

    /// Where a list line's text starts, in text-container coordinates.
    func listTextX(indent: Int) -> CGFloat {
        CGFloat(min(indent, Self.deepestIndent)) * indentStep + markerWidth
    }

    /// A line's look, given what it is and the kind of the line above it (nil on the page's first
    /// line), which decides the room above it.
    func displayAttributes(for block: BlockAttributes, inline: InlineStyle, kindAbove: BlockKind?) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: block.kind, inline: inline),
            .foregroundColor: foregroundColor(for: block, inline: inline),
            .paragraphStyle: paragraphStyle(for: block, kindAbove: kindAbove),
        ]
        let isDone = block.kind == .todo && block.isChecked
        if inline.contains(.strikethrough) || isDone {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = PlatformColor.secondaryText
        }
        if inline.contains(.code), block.kind != .code {
            attributes[.backgroundColor] = accent.withAlphaComponent(0.12)
        }
        return attributes
    }

    /// A link over its text's own look: in the page's colour, with a fine line under it in a
    /// paler shade. A link in a done to-do is as grey as the rest of the line.
    func linkAttributes(for block: BlockAttributes) -> [NSAttributedString.Key: Any] {
        let colour: PlatformColor = block.kind == .todo && block.isChecked ? .secondaryText : accent
        return [
            .foregroundColor: colour,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: colour.withAlphaComponent(0.4),
        ]
    }

    private func font(for kind: BlockKind, inline: InlineStyle) -> PlatformFont {
        if kind == .code { return codeFont }
        let base: PlatformFont = switch kind {
        case .heading1: heading1Font
        case .heading2: heading2Font
        case .heading3, .heading4, .heading5, .heading6: heading3Font
        default: bodyFont
        }
        if inline.contains(.code) {
            return PlatformFont.monospacedSystemFont(ofSize: base.pointSize * 0.88, weight: inline.contains(.bold) ? .semibold : .regular)
        }
        return base.adding(bold: inline.contains(.bold), italic: inline.contains(.italic))
    }

    private func foregroundColor(for block: BlockAttributes, inline: InlineStyle) -> PlatformColor {
        if block.kind == .todo, block.isChecked { return .secondaryText }
        if inline.contains(.code), block.kind != .code { return accent }
        return .primaryText
    }

    private func paragraphStyle(for block: BlockAttributes, kindAbove: BlockKind?) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let kind = block.kind
        style.lineSpacing = PageSpacing.rowGap(kind) * scale
        switch kind {
        case .bullet, .ordered, .todo:
            let x = listTextX(indent: block.indent)
            style.firstLineHeadIndent = x
            style.headIndent = x
        case .quote:
            style.firstLineHeadIndent = quoteIndent
            style.headIndent = quoteIndent
        case .code:
            style.firstLineHeadIndent = codeInset
            style.headIndent = codeInset
            style.tailIndent = -codeInset
        default:
            break
        }
        // All the room between two lines is the lower one's, so it can depend on both.
        if let kindAbove {
            style.paragraphSpacingBefore = max(0, roomAbove(kind, below: kindAbove))
        }
        return style
    }

    /// What TextKit needs above a line for the gap the page's spacing asks for (see
    /// `PageSpacing`). TextKit puts the line spacing above every row, so that comes off. A code
    /// block's gap is to its wash, which reaches `codePadding` past its text; a divider's is to
    /// its rule, drawn halfway up the capitals on its empty line.
    private func roomAbove(_ kind: BlockKind, below kindAbove: BlockKind) -> CGFloat {
        var gap = PageSpacing.gap(after: kindAbove, before: kind) * scale
        if kind == .code, kindAbove != .code { gap += codePadding }
        if kindAbove == .code, kind != .code { gap += codePadding }
        if kind == .divider { gap -= bodyFont.ascender - bodyFont.capHeight / 2 }
        if kindAbove == .divider { gap -= bodyFont.capHeight / 2 - bodyFont.descender }
        return gap - PageSpacing.rowGap(kind) * scale
    }
}
