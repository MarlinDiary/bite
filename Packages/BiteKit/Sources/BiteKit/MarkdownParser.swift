import Foundation

/// Reads Markdown into a document, one block per line.
///
/// It understands the subset Bite writes (see `MarkdownSerializer`) plus the usual variants
/// people paste in: `*` and `+` bullets, `1)` numbering, `[X]`, two-space nesting, `***` dividers.
public enum MarkdownParser {
    public static func parse(_ markdown: String) -> BiteDocument {
        var text = normalizedLineBreaks(markdown)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var lines = text.components(separatedBy: "\n")
        // The file's final newline ends the last line; it doesn't start a new one.
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }

        var blocks: [Block] = []
        var openFence: Fence?
        var fenceHadLines = false
        for line in lines {
            if let fence = openFence {
                if closesFence(line, fence) {
                    // An empty fenced block still shows as one empty code line.
                    if !fenceHadLines { blocks.append(Block(.code, language: fence.language)) }
                    openFence = nil
                } else {
                    blocks.append(Block(.code, line, language: fence.language))
                    fenceHadLines = true
                }
                continue
            }
            if let fence = opensFence(line) {
                openFence = fence
                fenceHadLines = false
                continue
            }
            blocks.append(block(for: line))
        }
        // A fence left open runs to the end of the file, and an empty one is still a block.
        if let fence = openFence, !fenceHadLines {
            blocks.append(Block(.code, language: fence.language))
        }
        // Until here a list item's indent is its width in spaces. Nesting follows the
        // indentation actually used, so 2-, 3- and 4-space styles all work.
        let levels = ListNesting.levels(for: blocks.map { ($0.kind, $0.indent) })
        for index in blocks.indices {
            blocks[index].indent = levels[index]
        }
        resolveSingleLetterMarkers(&blocks)
        // Only the number on a list's first item means anything, and 1 is where lists start
        // anyway.
        let starts = ListNumbering.startsList(blocks.map { ($0.kind, $0.indent, $0.numberStyle) })
        // Every item keeps its style, though only the first one's counts: when that one goes,
        // the next takes over in the same style.
        for index in blocks.indices where blocks[index].kind == .ordered {
            if !starts[index] || blocks[index].number == 1 { blocks[index].number = nil }
        }
        return BiteDocument(blocks: blocks)
    }

    /// One line read as text: its bold, italics and code come through, but a marker at its
    /// start (`- `, `# `, `1. `) stays as written. For text pasted into the middle of a line.
    public static func parseText(_ line: String) -> BiteDocument {
        BiteDocument(blocks: [Block(kind: .paragraph, runs: InlineParser.parse(line))])
    }

    /// A single-letter marker is read in the style of the list it's in when it's that list's
    /// next item: `v.` after `iv.` is five, `i.` after `h.` the ninth letter.
    private static func resolveSingleLetterMarkers(_ blocks: inout [Block]) {
        // As in `ListNumbering.numbers(for:)`, reading each item as it's reached.
        var counters: [ListNumbering.Number?] = []
        for index in blocks.indices {
            guard blocks[index].kind.isList else {
                counters.removeAll()
                continue
            }
            let level = max(0, blocks[index].indent)
            if counters.count > level + 1 {
                counters.removeLast(counters.count - level - 1)
            }
            while counters.count < level + 1 {
                counters.append(nil)
            }
            guard blocks[index].kind == .ordered else {
                counters[level] = nil
                continue
            }
            if let running = counters[level], let style = blocks[index].numberStyle,
               let reading = ListNumbering.reading(number: blocks[index].number ?? 1, style: style, asNextIn: running) {
                blocks[index].number = reading.ordinal
                blocks[index].numberStyle = reading.style
            }
            counters[level] = ListNumbering.next(after: counters[level], number: blocks[index].number, style: blocks[index].numberStyle)
        }
    }

    /// Every kind of line break as `\n`: Windows and old Mac files, and the Unicode separators
    /// that other apps put in copied text.
    public static func normalizedLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{85}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    /// A list item's indent comes back as its width in spaces (see `parse`).
    static func block(for line: String) -> Block {
        var width = 0
        var rest = Substring(line)
        while let first = rest.first, first == " " || first == "\t" {
            width += first == "\t" ? 4 : 1
            rest = rest.dropFirst()
        }

        // A backslash in front of a marker means "this is just text".
        if rest.first == "\\" {
            return Block(kind: .paragraph, runs: InlineParser.parse(line))
        }
        if width <= 3 {
            if MarkdownSyntax.isDivider(rest) {
                return Block(.divider)
            }
            if let heading = heading(in: rest) {
                return Block(kind: heading.kind, runs: InlineParser.parse(heading.content))
            }
            if rest.first == ">" {
                var content = rest.dropFirst()
                if content.first == " " { content = content.dropFirst() }
                return Block(kind: .quote, runs: InlineParser.parse(content))
            }
        }
        if let item = listItem(in: rest) {
            return Block(kind: item.kind, indent: width, isChecked: item.checked, number: item.number,
                         numberStyle: item.style, runs: InlineParser.parse(item.content))
        }
        return Block(kind: .paragraph, runs: InlineParser.parse(line))
    }

    private static func heading(in text: Substring) -> (kind: BlockKind, content: Substring)? {
        let hashes = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        var content = text.dropFirst(hashes)
        guard MarkdownSyntax.startsContent(content) else { return nil }
        if !content.isEmpty { content = content.dropFirst() }
        return (BlockKind.heading(level: hashes), content)
    }

    private static func listItem(in text: Substring) -> (kind: BlockKind, checked: Bool, number: Int?, style: NumberStyle?, content: Substring)? {
        guard let first = text.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let afterMarker = text.dropFirst()
            guard MarkdownSyntax.startsContent(afterMarker) else { return nil }
            let content = afterMarker.isEmpty ? afterMarker : afterMarker.dropFirst()
            for (marker, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where content.hasPrefix(marker) {
                let afterTask = content.dropFirst(marker.count)
                // Space or tab, as GFM has it and as the other markers take.
                if MarkdownSyntax.startsContent(afterTask) {
                    return (.todo, checked, nil, nil, afterTask.isEmpty ? afterTask : afterTask.dropFirst())
                }
            }
            return (.bullet, false, nil, nil, content)
        }
        guard let marker = MarkdownSyntax.orderedMarker(in: text) else { return nil }
        let afterMarker = text.dropFirst(marker.length)
        return (.ordered, false, marker.number, marker.style, afterMarker.isEmpty ? afterMarker : afterMarker.dropFirst())
    }

    // MARK: Code fences

    struct Fence {
        let character: Character
        let length: Int
        let language: String
    }

    /// Three or more backticks or tildes, then optionally a language (```` ```swift ````).
    private static func opensFence(_ line: String) -> Fence? {
        let leading = line.prefix(while: { $0 == " " })
        guard leading.count <= 3 else { return nil }
        let rest = line.dropFirst(leading.count)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let length = rest.prefix(while: { $0 == character }).count
        let info = rest.dropFirst(length)
        // A backtick fence can't have backticks after it; that would be inline code.
        guard length >= 3, character == "~" || !info.contains("`") else { return nil }
        return Fence(character: character, length: length, language: info.trimmingCharacters(in: .whitespaces))
    }

    private static func closesFence(_ line: String, _ fence: Fence) -> Bool {
        let leading = line.prefix(while: { $0 == " " })
        guard leading.count <= 3 else { return false }
        let rest = line.dropFirst(leading.count)
        let run = rest.prefix(while: { $0 == fence.character }).count
        return run >= fence.length && rest.dropFirst(run).allSatisfy(\.isWhitespace)
    }
}
