import Foundation

/// Turns a document into Markdown. This is the storage format, so it has to round-trip:
/// `MarkdownParser.parse(MarkdownSerializer.markdown(from: document)) == document`, for any
/// document Markdown can say (see `ListNesting`, and `inline` for the one place styling can
/// give way).
public enum MarkdownSerializer {
    /// The result ends with a newline unless the document has no blocks at all.
    public static func markdown(from document: BiteDocument) -> String {
        let blocks = document.blocks
        guard !blocks.isEmpty else { return "" }
        // Nesting Markdown can't say is pulled up first, so the file reads back as written and
        // other apps don't take a stray indented item for code.
        let levels = ListNesting.levels(for: blocks.map { ($0.kind, $0.indent) })
        let styles = writableStyles(blocks, levels: levels)
        let starts = ListNumbering.startsList(blocks.indices.map { (blocks[$0].kind, levels[$0], styles[$0]) })
        let numbers = ListNumbering.numbers(for: blocks.indices.map { (blocks[$0].kind, levels[$0], blocks[$0].number, styles[$0]) })
        var lines: [String] = []
        var index = 0
        while index < blocks.count {
            if blocks[index].kind == .code {
                // Code lines in a row are one block, under one fence. A line added on top of a
                // block has no language yet, so the first one named counts.
                var codeLines: [String] = []
                var language = ""
                while index < blocks.count, blocks[index].kind == .code {
                    codeLines.append(blocks[index].text)
                    if language.isEmpty { language = blocks[index].language }
                    index += 1
                }
                let fence = codeFence(for: codeLines, language: language)
                // A language starting with the fence's own character would read as part of it.
                lines.append(fence + (language.first == fence.first ? " " : "") + language)
                lines.append(contentsOf: codeLines)
                lines.append(fence)
                continue
            }
            let number = numbers[index] ?? ListNumbering.Number(ordinal: 1)
            let marker = ListNumbering.marker(for: number.ordinal, style: number.style, startsList: starts[index])
            lines.append(line(for: blocks[index], level: levels[index], marker: marker))
            index += 1
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The number styles as written: a list whose first number can't be written in its style
    /// is written in digits all through, or it would read back differently.
    static func writableStyles(_ blocks: [Block], levels: [Int]) -> [NumberStyle?] {
        let firstItems = ListNumbering.firstItems(for: blocks.indices.map { (blocks[$0].kind, levels[$0], blocks[$0].numberStyle) })
        return blocks.indices.map { index in
            guard let first = firstItems[index], let style = blocks[first].numberStyle else { return blocks[index].numberStyle }
            let marker = ListNumbering.marker(for: blocks[first].number ?? 1, style: style, startsList: true)
            return marker.first?.isNumber == true ? nil : blocks[index].numberStyle
        }
    }

    /// `marker` is what an ordered item is numbered with (`3.`, `c.`).
    static func line(for block: Block, level: Int, marker: String) -> String {
        let content = inline(block.runs)
        let indent = String(repeating: " ", count: level * 4)
        switch block.kind {
        case .paragraph: return escapeLineStart(content)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return prefixed(String(repeating: "#", count: block.kind.headingLevel ?? 1), content)
        case .bullet:
            var item = prefixed("-", escapeTaskMarker(content))
            // `- --` would read back as a divider. The text is then only dashes and spaces.
            if MarkdownSyntax.isDivider(Substring(item)), let dash = content.firstIndex(of: "-") {
                item = "- " + content[..<dash] + "\\" + content[dash...]
            }
            return indent + item
        case .ordered: return indent + prefixed(marker, content)
        case .todo: return indent + prefixed(block.isChecked ? "- [x]" : "- [ ]", content)
        case .quote: return prefixed(">", content)
        case .divider: return "---"
        case .code: return block.text
        }
    }

    private static func prefixed(_ marker: String, _ content: String) -> String {
        content.isEmpty ? marker : marker + " " + content
    }

    /// Longer than any run of the fence character that starts a line inside the block, and at
    /// least three. Backticks, unless the language itself has one.
    private static func codeFence(for lines: [String], language: String) -> String {
        let character: Character = language.contains("`") ? "~" : "`"
        var longest = 0
        for line in lines {
            let trimmed = line.drop(while: { $0 == " " })
            longest = max(longest, trimmed.prefix(while: { $0 == character }).count)
        }
        return String(repeating: character, count: max(3, longest + 1))
    }

    // MARK: Inline

    /// Bold and italic can't always change in the middle of a word: the `*` runs of both sides
    /// merge and can read back paired up differently, even per CommonMark. So when styles meet
    /// with no space between, the result is read back to check, and if it doesn't hold, the
    /// least styling is let go that makes it hold. Losing a style beats stray asterisks turning
    /// up in the text.
    static func inline(_ runs: [InlineRun]) -> String {
        let markdown = encode(runs)
        guard emphasisChangesMidWord(runs), !readsBack(markdown, as: runs) else { return markdown }
        for dropped: InlineStyle in [.italic, .bold, [.bold, .italic]] {
            let simpler = droppingEmphasisChanges(dropped, from: runs)
            let attempt = encode(simpler)
            if readsBack(attempt, as: simpler) { return attempt }
        }
        return encode(runs.map { InlineRun($0.text, style: $0.style.subtracting([.bold, .italic])) })
    }

    /// Words and the whitespace between them, whitespace unstyled: its style doesn't show, and
    /// Markdown can't always say it. Two lines that look the same have the same words.
    public static func words(_ runs: [InlineRun]) -> [InlineRun] {
        var words: [InlineRun] = []
        for run in runs {
            var current = ""
            var currentIsSpace: Bool?
            for character in run.text {
                let isSpace = character.isWhitespace
                if let wasSpace = currentIsSpace, wasSpace != isSpace {
                    words.append(InlineRun(current, style: wasSpace ? [] : run.style))
                    current = ""
                }
                current.append(character)
                currentIsSpace = isSpace
            }
            if let wasSpace = currentIsSpace {
                words.append(InlineRun(current, style: wasSpace ? [] : run.style))
            }
        }
        return InlineRun.normalized(words)
    }

    private static func readsBack(_ markdown: String, as runs: [InlineRun]) -> Bool {
        words(InlineParser.parse(markdown)) == words(runs)
    }

    private static let emphasis: InlineStyle = [.bold, .italic]

    /// True when bold or italic starts or stops between two characters that aren't whitespace.
    /// Only then can saving let a style go (see `inline`).
    public static func emphasisChangesMidWord(_ runs: [InlineRun]) -> Bool {
        // Only where runs of different emphasis meet; most lines have one run.
        guard let first = runs.first?.style.intersection(emphasis),
              runs.contains(where: { $0.style.intersection(emphasis) != first }) else { return false }
        let words = words(runs)
        return zip(words, words.dropFirst()).contains { left, right in
            !left.text.allSatisfy(\.isWhitespace) && !right.text.allSatisfy(\.isWhitespace)
                && left.style.intersection(emphasis) != right.style.intersection(emphasis)
        }
    }

    /// Takes `dropped` off every stretch of touching words where bold or italic changes.
    private static func droppingEmphasisChanges(_ dropped: InlineStyle, from runs: [InlineRun]) -> [InlineRun] {
        var words = words(runs)
        var start = 0
        while start < words.count {
            var end = start
            while end + 1 < words.count, !words[end].text.allSatisfy(\.isWhitespace),
                  !words[end + 1].text.allSatisfy(\.isWhitespace) {
                end += 1
            }
            let styles = Set(words[start...end].map { $0.style.intersection(emphasis).rawValue })
            if styles.count > 1 {
                for index in start...end { words[index].style.subtract(dropped) }
            }
            start = end + 1
        }
        return InlineRun.normalized(words)
    }

    private static func encode(_ runs: [InlineRun]) -> String {
        struct Segment {
            var text: String
            var style: InlineStyle
            var isSpace: Bool
        }
        // Delimiters can't sit next to whitespace on their inner side, so leading and trailing
        // whitespace is pulled out of every styled run.
        var segments: [Segment] = []
        for run in InlineRun.normalized(runs) {
            let (leading, core, trailing) = splitWhitespace(run.text)
            if !leading.isEmpty { segments.append(Segment(text: leading, style: [], isSpace: true)) }
            if !core.isEmpty { segments.append(Segment(text: core, style: run.style, isSpace: false)) }
            if !trailing.isEmpty { segments.append(Segment(text: trailing, style: [], isSpace: true)) }
        }

        let order: [InlineStyle] = [.bold, .italic, .strikethrough]
        // Text is escaped once what's around it is known (see `escape`), so pieces come first.
        var pieces: [(text: String, isText: Bool)] = []
        var open: [InlineStyle] = []
        func close(keeping keep: InlineStyle) {
            guard let first = open.firstIndex(where: { !keep.contains($0) }) else { return }
            for style in open[first...].reversed() {
                pieces.append((delimiter(for: style), false))
            }
            open.removeSubrange(first...)
        }

        for (index, segment) in segments.enumerated() {
            if segment.isSpace {
                // Keep open only what the next word continues with.
                let next = segments[(index + 1)...].first(where: { !$0.isSpace })?.style ?? []
                close(keeping: next)
                pieces.append((segment.text, false))
                continue
            }
            let target = segment.style.subtracting(.code)
            close(keeping: target)
            for style in order where target.contains(style) && !open.contains(style) {
                pieces.append((delimiter(for: style), false))
                open.append(style)
            }
            pieces.append(segment.style.contains(.code) ? (codeSpan(segment.text), false) : (segment.text, true))
        }
        close(keeping: [])

        var output = ""
        for (index, piece) in pieces.enumerated() {
            guard piece.isText else {
                output += piece.text
                continue
            }
            let after = pieces[(index + 1)...].first(where: { !$0.text.isEmpty })?.text.first
            output += escape(piece.text, before: output.last, after: after)
        }
        return output
    }

    private static func delimiter(for style: InlineStyle) -> String {
        switch style {
        case .bold: "**"
        case .italic: "*"
        default: "~~"
        }
    }

    private static func codeSpan(_ text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let needsPadding = text.hasPrefix("`") || text.hasSuffix("`")
        return needsPadding ? fence + " " + text + " " + fence : fence + text + fence
    }

    /// `before` and `after` are what's written either side of the text: a delimiter, a space
    /// or other text.
    private static func escape(_ text: String, before: Character?, after: Character?) -> String {
        // Most text has nothing to escape. The characters that may need it are all ASCII.
        guard text.utf8.contains(where: { $0 == 0x5C || $0 == 0x2A || $0 == 0x60 || $0 == 0x7E || $0 == 0x5F }) else {
            return text
        }
        let characters = Array(text)
        var output = ""
        for (index, character) in characters.enumerated() {
            switch character {
            case "\\", "*", "`":
                output += "\\" + String(character)
            case "~":
                // A tilde next to another, the text's own or a `~~` delimiter beside it, would
                // read back as part of a strikethrough run. Whether one is beside it is known
                // now: escaping every tilde at the edge of a run wrote a backslash that was gone
                // after the page was read back and saved again.
                let previous = index > 0 ? characters[index - 1] : before
                let next = index < characters.count - 1 ? characters[index + 1] : after
                output += previous == "~" || next == "~" ? "\\~" : "~"
            case "_":
                // Underscores only emphasise at the edge of a word, so snake_case stays as it
                // is. At either end the neighbour is unknown: it may be a delimiter.
                var start = index
                while start > 0, characters[start - 1] == "_" { start -= 1 }
                var end = index
                while end < characters.count - 1, characters[end + 1] == "_" { end += 1 }
                let insideWord = start > 0 && end < characters.count - 1
                    && characters[start - 1].isLetterOrNumber && characters[end + 1].isLetterOrNumber
                output += insideWord ? "_" : "\\_"
            default:
                output.append(character)
            }
        }
        return output
    }

    private static func splitWhitespace(_ text: String) -> (String, String, String) {
        let leading = text.prefix(while: \.isWhitespace)
        let rest = text.dropFirst(leading.count)
        let trailingCount = rest.reversed().prefix(while: \.isWhitespace).count
        return (String(leading), String(rest.dropLast(trailingCount)), String(rest.suffix(trailingCount)))
    }

    // MARK: Escaping block markers

    /// A paragraph that happens to start like a block marker gets a backslash so it stays a paragraph.
    static func escapeLineStart(_ line: String) -> String {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(leading.count)
        guard let first = rest.first else { return line }
        let escaped = String(leading) + "\\" + rest
        switch first {
        case "#":
            let hashes = rest.prefix(while: { $0 == "#" }).count
            if hashes <= 6, MarkdownSyntax.startsContent(rest.dropFirst(hashes)) { return escaped }
        case "-", "+", "*":
            if MarkdownSyntax.startsContent(rest.dropFirst()) || MarkdownSyntax.isDivider(rest) { return escaped }
        case "_":
            if MarkdownSyntax.isDivider(rest) { return escaped }
        case ">":
            return escaped
        default:
            // `1. `, `a. ` or `iv. `: a backslash before the dot.
            if let marker = MarkdownSyntax.orderedMarker(in: rest) {
                let digits = rest.prefix(marker.length - 1)
                return String(leading) + digits + "\\" + rest.dropFirst(digits.count)
            }
        }
        return line
    }

    /// A bullet whose text starts with `[ ]` would read back as a to-do.
    private static func escapeTaskMarker(_ content: String) -> String {
        for marker in ["[ ]", "[x]", "[X]"] where content.hasPrefix(marker) {
            if MarkdownSyntax.startsContent(content.dropFirst(marker.count)) {
                return "\\" + content
            }
        }
        return content
    }
}

enum MarkdownSyntax {
    /// `---`, `***`, `___`, also with spaces in between.
    static func isDivider(_ line: Substring) -> Bool {
        let characters = line.filter { $0 != " " && $0 != "\t" }
        guard characters.count >= 3, let first = characters.first, "-*_".contains(first) else { return false }
        return characters.allSatisfy { $0 == first }
    }

    /// True when a block marker right before `text` would be recognised.
    static func startsContent(_ text: Substring) -> Bool {
        text.isEmpty || text.first == " " || text.first == "\t"
    }

    /// An ordered item's marker at the start of `text` (`12.`, `3)`, `b.`, `iv)`), with how many
    /// characters it takes, the dot or parenthesis included.
    static func orderedMarker(in text: Substring) -> (length: Int, number: Int, style: NumberStyle?)? {
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        let letters = text.prefix(while: { $0.isASCII && $0.isLetter })
        let label = digits.isEmpty ? letters : digits
        guard !label.isEmpty else { return nil }
        let rest = text.dropFirst(label.count)
        guard let end = rest.first, end == "." || end == ")", startsContent(rest.dropFirst()) else { return nil }
        if !digits.isEmpty {
            guard digits.count <= 9, let number = Int(digits) else { return nil }
            return (digits.count + 1, number, nil)
        }
        guard let value = ListNumbering.value(ofMarker: letters) else { return nil }
        return (letters.count + 1, value.number, value.style)
    }
}
