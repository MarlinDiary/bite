import UIKit
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
    /// Derived: the number shown in front of an ordered item (Int).
    static let biteOrdinal = NSAttributedString.Key("bite.ordinal")
    /// Derived: `RunPosition.rawValue` (Int).
    static let biteRunPosition = NSAttributedString.Key("bite.runPosition")
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
/// block's rounded corners and spacing, and where a quote's bar starts and stops.
nonisolated enum RunPosition: Int, Sendable {
    case single, first, middle, last

    var isFirst: Bool { self == .single || self == .first }
    var isLast: Bool { self == .single || self == .last }
}

/// Fonts, colours and spacing for the editor. Display attributes are always derived from the
/// block and inline attributes through here, never stored on their own.
nonisolated struct EditorTheme: @unchecked Sendable {
    let accent: UIColor
    let bodyFont = UIFont.systemFont(ofSize: 17)
    let heading1Font = UIFont.systemFont(ofSize: 28, weight: .bold)
    let heading2Font = UIFont.systemFont(ofSize: 22, weight: .bold)
    let heading3Font = UIFont.systemFont(ofSize: 19, weight: .semibold)
    let codeFont = UIFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
    let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)

    /// Room between a list line's indent and its text, where the marker is drawn.
    let markerWidth: CGFloat = 28
    let indentStep: CGFloat = 24
    let quoteIndent: CGFloat = 18
    let codeInset: CGFloat = 14
    let codePadding: CGFloat = 9

    init(accent: UIColor) {
        self.accent = accent
    }

    /// A deeper shade of the page's own wash, where a neutral grey looked like a dull film over
    /// the coloured pages. See-through, over the wash.
    var codeBackground: UIColor {
        let accent = accent
        return UIColor { traits in
            accent.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.10 : 0.09)
        }
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

    func displayAttributes(for block: BlockAttributes, inline: InlineStyle, runPosition: RunPosition) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: block.kind, inline: inline),
            .foregroundColor: foregroundColor(for: block, inline: inline),
            .paragraphStyle: paragraphStyle(for: block, runPosition: runPosition),
        ]
        let isDone = block.kind == .todo && block.isChecked
        if inline.contains(.strikethrough) || isDone {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = UIColor.secondaryLabel
        }
        if inline.contains(.code), block.kind != .code {
            attributes[.backgroundColor] = accent.withAlphaComponent(0.12)
        }
        return attributes
    }

    private func font(for kind: BlockKind, inline: InlineStyle) -> UIFont {
        if kind == .code { return codeFont }
        let base: UIFont = switch kind {
        case .heading1: heading1Font
        case .heading2: heading2Font
        case .heading3, .heading4, .heading5, .heading6: heading3Font
        default: bodyFont
        }
        if inline.contains(.code) {
            return UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.88, weight: inline.contains(.bold) ? .semibold : .regular)
        }
        var traits = base.fontDescriptor.symbolicTraits
        if inline.contains(.bold) { traits.insert(.traitBold) }
        if inline.contains(.italic) { traits.insert(.traitItalic) }
        guard traits != base.fontDescriptor.symbolicTraits,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    private func foregroundColor(for block: BlockAttributes, inline: InlineStyle) -> UIColor {
        if block.kind == .todo, block.isChecked { return .secondaryLabel }
        if inline.contains(.code), block.kind != .code { return accent }
        return .label
    }

    private func paragraphStyle(for block: BlockAttributes, runPosition: RunPosition) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 8
        switch block.kind {
        case .paragraph:
            break
        case .heading1:
            style.lineSpacing = 2
            style.paragraphSpacingBefore = 14
            style.paragraphSpacing = 6
        case .heading2:
            style.lineSpacing = 2
            style.paragraphSpacingBefore = 10
            style.paragraphSpacing = 6
        case .heading3, .heading4, .heading5, .heading6:
            style.lineSpacing = 2
            style.paragraphSpacingBefore = 6
            style.paragraphSpacing = 4
        case .bullet, .ordered, .todo:
            let x = listTextX(indent: block.indent)
            style.firstLineHeadIndent = x
            style.headIndent = x
            style.paragraphSpacing = 6
        case .quote:
            style.firstLineHeadIndent = quoteIndent
            style.headIndent = quoteIndent
            style.paragraphSpacing = 6
        case .code:
            style.firstLineHeadIndent = codeInset
            style.headIndent = codeInset
            style.tailIndent = -codeInset
            style.lineSpacing = 2
            style.paragraphSpacingBefore = runPosition.isFirst ? 14 : 0
            style.paragraphSpacing = runPosition.isLast ? 14 : 0
        case .divider:
            style.paragraphSpacingBefore = 4
            style.paragraphSpacing = 10
        }
        return style
    }
}
