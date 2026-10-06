import Foundation

/// Text added to the end of a page from outside the editor, as from Siri or Shortcuts: as if it
/// were typed there, the caret at the end of the page. An empty last line, a paragraph or a list
/// item, takes it as it is; after a line with something on it, it goes on a new line, carrying on
/// a list the page ends with, as Return does. Each line of the text is a line of the page, as
/// written: Markdown in it is kept as text, as typing it would only through the format bar.
public enum PageAddition {
    /// `markdown` with `text` added, as a to-do whatever the page ends with if `asToDo`. The same
    /// Markdown when there's nothing to add.
    public static func markdown(_ markdown: String, adding text: String, asToDo: Bool) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return markdown }
        var blocks = MarkdownParser.parse(markdown).blocks
        for line in lines {
            add(line, asToDo: asToDo, to: &blocks)
        }
        return MarkdownSerializer.markdown(from: BiteDocument(blocks: blocks))
    }

    private static func add(_ text: String, asToDo: Bool, to blocks: inout [Block]) {
        guard let last = blocks.last else {
            blocks.append(Block(asToDo ? .todo : .paragraph, text))
            return
        }
        let takesText = last.kind == .paragraph || last.kind.isList
        if last.text.isEmpty, takesText {
            blocks[blocks.count - 1] = line(text, like: last, asToDo: asToDo, keepsNumber: true)
        } else if last.kind.isList {
            blocks.append(line(text, like: last, asToDo: asToDo, keepsNumber: false))
        } else {
            blocks.append(Block(asToDo ? .todo : .paragraph, text))
        }
    }

    /// A line of `other`'s kind at its level, or a to-do there: unticked, and in a numbered list,
    /// numbered on from it, or as it was when it's `other` filled in.
    private static func line(_ text: String, like other: Block, asToDo: Bool, keepsNumber: Bool) -> Block {
        let kind: BlockKind = asToDo ? .todo : other.kind
        let ordered = kind == .ordered
        return Block(kind, text, indent: other.indent, number: ordered && keepsNumber ? other.number : nil,
                     numberStyle: ordered ? other.numberStyle : nil)
    }
}
