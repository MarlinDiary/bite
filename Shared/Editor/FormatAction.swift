import BiteKit

/// What the format bar's buttons, and on a Mac the Format menu, do to the page.
enum FormatAction: CaseIterable {
    case todo, bullet, ordered, heading, quote, code, bold, italic, strikethrough, link, outdent, indent, dismiss

    var symbol: String {
        switch self {
        case .todo: "checklist"
        case .bullet: "list.bullet"
        case .ordered: "list.number"
        case .heading: "textformat.size"
        case .quote: "text.quote"
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
