import BiteKit

/// What the format bar's buttons, and on a Mac the Format menu, do to the page. In the order the
/// bar has them: the first six across it as it comes up, the rest a scroll away.
enum FormatAction: CaseIterable {
    case heading, todo, bold, italic, strikethrough, link, quote, code, outdent, indent, ordered, bullet, dismiss

    var symbol: String {
        switch self {
        case .todo: "checklist"
        case .bullet: "list.bullet"
        case .ordered: "list.number"
        case .heading: "textformat"
        // Bite's own (Shared/Symbols.xcassets): a bar beside a block, as Notes draws its block
        // quote, with a symbol of the system's private to it (user, 2026-10-08).
        case .quote: "bite.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .link: "link"
        case .outdent: "decrease.indent"
        case .indent: "increase.indent"
        case .dismiss: "keyboard.chevron.compact.down"
        }
    }

    var title: String {
        switch self {
        case .todo: "To-do"
        case .bullet: "Bulleted List"
        case .ordered: "Numbered List"
        case .heading: "Heading"
        case .quote: "Quote"
        case .code: "Code Block"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .link: "Link"
        case .outdent: "Outdent"
        case .indent: "Indent"
        case .dismiss: "Hide Keyboard"
        }
    }

    /// Whether `symbol` is Bite's own, in its asset catalog, rather than one of the system's. It's
    /// drawn in layers, the block lighter than the bar.
    var hasOwnSymbol: Bool {
        self == .quote
    }

    /// The inline style the button sets. It shows as on while typing gets that style, or while
    /// all the selected text has it.
    var style: InlineStyle? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .strikethrough: .strikethrough
        default: nil
        }
    }
}
