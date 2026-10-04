/// A page as plain text, for pasting where Markdown doesn't read: the page as it shows, without
/// the Markdown. Lists keep their bullets and numbers as they're drawn, to-dos get a box, and a
/// divider is a line of dashes. Bold, italic, code, headings and quotes are just their text. A
/// link is its text with where it goes after it in parentheses, unless the text says that already.
public enum PlainTextSerializer {
    public static func plainText(from document: BiteDocument) -> String {
        let numbers = ListNumbering.numbers(for: document.blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        var lines = document.blocks.indices.map { index in
            let block = document.blocks[index]
            let indent = String(repeating: "    ", count: max(0, block.indent))
            let text = text(of: block.runs)
            switch block.kind {
            case .bullet:
                return indent + bullets[max(0, block.indent) % bullets.count] + " " + text
            case .ordered:
                let number = numbers[index]
                return indent + ListNumbering.label(for: number?.ordinal ?? 1, indent: block.indent, style: number?.style) + " " + text
            case .todo:
                return indent + (block.isChecked ? "\u{2611}" : "\u{2610}") + " " + text
            case .divider:
                return "\u{2014}\u{2014}\u{2014}"
            default:
                return indent + text
            }
        }
        // Empty lines left at the end of the page aren't part of what's copied.
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func text(of runs: [InlineRun]) -> String {
        var text = ""
        for (index, run) in runs.enumerated() {
            text += run.text
            guard let link = run.link, !link.isEmpty, index + 1 == runs.count || runs[index + 1].link != link else { continue }
            // The whole of the link's text, which may be in several styles.
            var start = index
            while start > 0, runs[start - 1].link == link { start -= 1 }
            if runs[start...index].map(\.text).joined() != link {
                text += " (" + link + ")"
            }
        }
        return text
    }

    /// The editor draws a dot, a ring and a square, going round by level, as Notion does.
    private static let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
}
