/// A page as plain text, for pasting where Markdown doesn't read: the page as it shows, without
/// the Markdown. Lists keep their bullets and numbers as they're drawn, to-dos get a box, and a
/// divider is a line of dashes. Bold, italic, code, headings and quotes are just their text.
public enum PlainTextSerializer {
    public static func plainText(from document: BiteDocument) -> String {
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        var lines = document.blocks.indices.map { index in
            let block = document.blocks[index]
            let indent = String(repeating: "    ", count: max(0, block.indent))
            switch block.kind {
            case .bullet:
                return indent + bullets[max(0, block.indent) % bullets.count] + " " + block.text
            case .ordered:
                let number = numbers[index]
                return indent + ListNumbering.label(for: number?.ordinal ?? 1, indent: block.indent, style: number?.style) + " " + block.text
            case .todo:
                return indent + (block.isChecked ? "\u{2611}" : "\u{2610}") + " " + block.text
            case .divider:
                return "\u{2014}\u{2014}\u{2014}"
            default:
                return indent + block.text
            }
        }
        // Empty lines left at the end of the page aren't part of what's copied.
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// The editor draws a dot, a ring and a square, going round by level, as Notion does.
    private static let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
}
