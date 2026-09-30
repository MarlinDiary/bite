/// The Notion-style editing rules, as plain functions so every platform's editor shares them
/// and they can be tested without a text view.
public enum InputRules {
    public struct BlockChange: Equatable, Sendable {
        public var kind: BlockKind
        public var isChecked: Bool
        /// The number typed for an ordered item (`3.`), where a new list starts.
        public var number: Int?
        /// Set when the list was started with a letter or Roman numeral.
        public var numberStyle: NumberStyle?

        public init(_ kind: BlockKind, checked: Bool = false, number: Int? = nil, numberStyle: NumberStyle? = nil) {
            self.kind = kind
            self.isChecked = checked
            self.number = number
            self.numberStyle = numberStyle
        }
    }

    // MARK: Block shortcuts

    // A Chinese keyboard has no `>`, `[`, `]` or backtick, and types some punctuation full
    // width, so the markers also come in the forms it types: a right double angle bracket
    // (U+300B) for a quote, lenticular brackets (U+3010, U+3011) for a to-do, the ideographic
    // full stop (U+3002) or a full-width parenthesis after a number, middle dots (U+00B7) for
    // code and full-width tildes (U+FF5E) for strikethrough. Full-width `#`, `-`, `*`, `+` and
    // `>` come from other keyboards. A quotation mark also makes a quote, as in Notion,
    // straight or curly (U+201C), which is what smart quotes and Chinese keyboards type.

    /// A marker typed at the start of a line and confirmed with a space.
    /// `prefix` is the text between the start of the line and the caret.
    public static func blockShortcut(forPrefix prefix: String) -> BlockChange? {
        switch prefix {
        case "-", "*", "+", "•", "\u{00B7}", "\u{FF0D}", "\u{FF0A}", "\u{FF0B}": return BlockChange(.bullet)
        case ">", "\u{300B}", "\u{FF1E}", "\"", "\u{201C}": return BlockChange(.quote)
        case "[]", "[ ]", "\u{3010}\u{3011}", "\u{3010} \u{3011}": return BlockChange(.todo)
        case "[x]", "[X]", "\u{3010}x\u{3011}", "\u{3010}X\u{3011}": return BlockChange(.todo, checked: true)
        default:
            if !prefix.isEmpty, prefix.count <= 6, prefix.allSatisfy({ $0 == "#" || $0 == "\u{FF03}" }) {
                return BlockChange(.heading(level: prefix.count))
            }
            return orderedMarker(prefix)
        }
    }

    /// An ordered marker such as `3.` or `3)`, or `a.` or `i.`, which start a list in letters
    /// or Roman numerals as in Notion. Capitals too, since the keyboard capitalizes the start
    /// of a line. Other letters stay text, so `P. S.` is left alone.
    private static func orderedMarker(_ text: String) -> BlockChange? {
        guard let last = text.last, [".", ")", "\u{3002}", "\u{FF0E}", "\u{FF09}"].contains(last) else { return nil }
        let label = text.dropLast()
        switch label {
        case "a": return BlockChange(.ordered, numberStyle: .letters)
        case "A": return BlockChange(.ordered, numberStyle: .capitalLetters)
        case "i": return BlockChange(.ordered, numberStyle: .roman)
        case "I": return BlockChange(.ordered, numberStyle: .capitalRoman)
        default:
            guard (1...9).contains(label.count), label.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(label)).map { BlockChange(.ordered, number: $0) }
        }
    }

    /// `---` makes a divider and three backticks, or three middle dots, start a code block. An
    /// em dash counts as two hyphens, in case something turned `--` into one.
    public static func lineShortcut(forPrefix prefix: String, typed: String) -> BlockKind? {
        switch (prefix, typed) {
        case ("--", "-"), ("—", "-"): .divider
        case ("``", "`"), ("\u{00B7}\u{00B7}", "\u{00B7}"): .code
        default: nil
        }
    }

    /// Three backticks (or middle dots) on an otherwise empty line inside a code block close
    /// it, like a Markdown fence: the line becomes a paragraph.
    public static func closesCodeBlock(prefix: String, typed: String) -> Bool {
        (prefix == "``" && typed == "`") || (prefix == "\u{00B7}\u{00B7}" && typed == "\u{00B7}")
    }

    // MARK: Inline shortcuts

    public struct InlineMatch: Equatable, Sendable {
        /// UTF-16 offsets into `prefix + typed`: the whole match, markers included.
        public var range: Range<Int>
        /// UTF-16 offsets of the text between the markers.
        public var content: Range<Int>
        public var style: InlineStyle
    }

    /// The characters that can close an inline shortcut.
    public static let inlineMarkers: Set<String> = ["*", "_", "`", "~", "\u{FF5E}"]

    /// Checks whether typing `typed` closes `**bold**`, `*italic*`, `__bold__`, `_italic_`,
    /// `~~strike~~` or `` `code` ``. `prefix` is the text of the line before the caret and
    /// `following` the character after it, if there is one.
    ///
    /// The line is read as `InlineParser` reads Markdown, so typing it gives what pasting it
    /// would: a backslash makes the marker after it text; a backtick still open before the
    /// caret may yet start code, which holds no emphasis; and letters, digits and spaces are
    /// told apart by whole characters, in any script.
    public static func inlineShortcut(prefix: String, typed: String, following: Character? = nil) -> InlineMatch? {
        let line = TypedLine(prefix + typed)
        switch typed {
        case "*": return emphasisMatch(line, marker: star, onlyAtWordEdges: false, following: following)
        case "_": return emphasisMatch(line, marker: underscore, onlyAtWordEdges: true, following: following)
        case "`": return codeMatch(line)
        case "~": return tildeMatch(line, tilde: tilde)
        case "\u{FF5E}": return tildeMatch(line, tilde: fullWidthTilde)
        default: return nil
        }
    }

    private static let star = UInt16(UInt8(ascii: "*"))
    private static let underscore = UInt16(UInt8(ascii: "_"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let tilde = UInt16(UInt8(ascii: "~"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let fullWidthTilde: UInt16 = 0xFF5E

    /// A line typed up to and including the character just typed, in UTF-16 units, which the
    /// match offsets count.
    private struct TypedLine {
        let text: String
        let units: [UInt16]

        init(_ text: String) {
            self.text = text
            units = Array(text.utf16)
        }

        var count: Int { units.count }

        subscript(index: Int) -> UInt16 { units[index] }

        /// Whether the character at `index` is escaped: an odd number of backslashes before it.
        func isEscaped(_ index: Int) -> Bool {
            var backslashes = 0
            var position = index - 1
            while position >= 0, units[position] == InputRules.backslash {
                backslashes += 1
                position -= 1
            }
            return backslashes % 2 == 1
        }

        /// Any Unicode space, as `Character.isWhitespace` has it. Spaces are all single units.
        func isSpace(_ index: Int) -> Bool {
            Unicode.Scalar(units[index])?.properties.isWhitespace ?? false
        }

        func hasTrimmedContent(_ range: Range<Int>) -> Bool {
            !range.isEmpty && !isSpace(range.lowerBound) && !isSpace(range.upperBound - 1)
        }

        /// The whole character ending at `offset`. A letter beyond the Basic Multilingual Plane,
        /// like many CJK characters, takes two units, and one of those alone isn't a letter.
        func character(before offset: Int) -> Character? {
            guard offset > 0 else { return nil }
            return text[..<String.Index(utf16Offset: offset, in: text)].last
        }

        /// The backtick run still open before `end`, if there is one: what follows it may yet be
        /// code. As in Markdown, a backslash makes a backtick that would open code just text, but
        /// inside code it's only a backslash.
        func openCode(before end: Int) -> (start: Int, length: Int)? {
            var open: (start: Int, length: Int)?
            var index = 0
            while index < end {
                guard units[index] == InputRules.backtick else {
                    index += 1
                    continue
                }
                if open == nil, isEscaped(index) {
                    index += 1
                    continue
                }
                var length = 1
                while index + length < end, units[index + length] == InputRules.backtick {
                    length += 1
                }
                if let current = open {
                    if current.length == length { open = nil }
                } else {
                    open = (index, length)
                }
                index += length
            }
            return open
        }
    }

    /// `**bold**` and `*italic*`, or with underscores. An underscore only opens at the start
    /// of a word and closes at its end, as in Markdown, so snake_case stays as typed.
    private static func emphasisMatch(_ line: TypedLine, marker: UInt16, onlyAtWordEdges: Bool, following: Character?) -> InlineMatch? {
        let count = line.count
        guard count >= 3, !line.isEscaped(count - 1), line.openCode(before: count - 1) == nil else { return nil }
        if onlyAtWordEdges, following?.isLetterOrNumber == true { return nil }
        func opensHere(_ index: Int) -> Bool {
            !onlyAtWordEdges || !(line.character(before: index)?.isLetterOrNumber ?? false)
        }
        if line[count - 2] == marker {
            // Closing pair: the nearest opening pair decides.
            guard !line.isEscaped(count - 2) else { return nil }
            var index = count - 4
            while index >= 0 {
                if line[index] == marker, line[index + 1] == marker, index == 0 || line[index - 1] != marker,
                   !line.isEscaped(index), opensHere(index) {
                    let content = (index + 2)..<(count - 2)
                    guard line.hasTrimmedContent(content) else { return nil }
                    return InlineMatch(range: index..<count, content: content, style: .bold)
                }
                index -= 1
            }
            return nil
        }
        // Closing single: the nearest marker must be a single one, or the user is still typing
        // a pair. An escaped marker is text, and the search goes on past it.
        var index = count - 3
        while index >= 0 {
            if line[index] == marker, !line.isEscaped(index) {
                guard index == 0 || line[index - 1] != marker, line[index + 1] != marker else { return nil }
                if opensHere(index) {
                    let content = (index + 1)..<(count - 1)
                    guard line.hasTrimmedContent(content) else { return nil }
                    return InlineMatch(range: index..<count, content: content, style: .italic)
                }
            }
            index -= 1
        }
        return nil
    }

    /// A single backtick closes the code the nearest open one started. Only single ones: a run
    /// of two or more needs one as long to close it, which typing one at a time can't tell.
    private static func codeMatch(_ line: TypedLine) -> InlineMatch? {
        let count = line.count
        guard count >= 3, line[count - 2] != backtick, let open = line.openCode(before: count - 1), open.length == 1 else { return nil }
        let content = (open.start + 1)..<(count - 1)
        guard content.contains(where: { !line.isSpace($0) }) else { return nil }
        return InlineMatch(range: open.start..<count, content: content, style: .code)
    }

    private static func tildeMatch(_ line: TypedLine, tilde: UInt16) -> InlineMatch? {
        let count = line.count
        guard count >= 5, line[count - 2] == tilde, !line.isEscaped(count - 2),
              line.openCode(before: count - 1) == nil else { return nil }
        var index = count - 4
        while index >= 0 {
            if line[index] == tilde, line[index + 1] == tilde, index == 0 || line[index - 1] != tilde, !line.isEscaped(index) {
                let content = (index + 2)..<(count - 2)
                guard line.hasTrimmedContent(content) else { return nil }
                return InlineMatch(range: index..<count, content: content, style: .strikethrough)
            }
            index -= 1
        }
        return nil
    }

    // MARK: Return and backspace

    /// What Return does. Lists and quotes carry on to the next line, and so does code, which is
    /// multi-line by nature; an empty line ends them. Headings go on as a plain paragraph.
    public enum ReturnAction: Equatable, Sendable {
        /// Plain text behaviour.
        case insertNewline
        /// List, quote or code: split the line and keep its kind. A new to-do starts unchecked.
        case continueBlock
        /// Caret at the start of a list item or quote line with text: open an empty one above it.
        case itemAbove
        /// Empty line: turn it back into a paragraph.
        case exitBlock
        /// Empty nested list item: move it up one level.
        case outdent
        /// Heading or divider: whatever follows the caret goes on a new paragraph.
        case splitToParagraph
        /// Caret at the start of a heading with text: open a paragraph above it.
        case paragraphAbove
    }

    /// `nextKind` is the kind of the line below, if there is one.
    public static func returnAction(kind: BlockKind, indent: Int, lineIsEmpty: Bool, caretAtStart: Bool, nextKind: BlockKind? = nil) -> ReturnAction {
        switch kind {
        case .bullet, .ordered, .todo, .quote:
            if lineIsEmpty { return indent > 0 ? .outdent : .exitBlock }
            return caretAtStart ? .itemAbove : .continueBlock
        case .code:
            // A blank line inside the block is fine; a blank last line ends the block.
            return lineIsEmpty && nextKind != .code ? .exitBlock : .continueBlock
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            if lineIsEmpty { return .exitBlock }
            return caretAtStart ? .paragraphAbove : .splitToParagraph
        case .divider:
            return .splitToParagraph
        case .paragraph:
            return .insertNewline
        }
    }

    public enum BackspaceAction: Equatable, Sendable {
        case deleteCharacter
        case outdent
        case convertToParagraph
        /// The line above is a divider, which goes instead.
        case deleteLineAbove
    }

    /// Backspace with the caret at the very start of a line. `previousKind` is the kind of the
    /// line above, if there is one.
    public static func backspaceAtLineStart(kind: BlockKind, indent: Int, previousKind: BlockKind? = nil) -> BackspaceAction {
        if kind.isList, indent > 0 { return .outdent }
        // Inside a code block a line joins the one above, as in any code editor.
        if kind == .code, previousKind == .code { return .deleteCharacter }
        guard kind == .paragraph else { return .convertToParagraph }
        // A divider holds no text, so rather than take this line in, it goes. That's the way to
        // delete one, since the caret never rests on it.
        return previousKind == .divider ? .deleteLineAbove : .deleteCharacter
    }
}
