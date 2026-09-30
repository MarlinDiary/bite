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
    /// `~~strike~~` or `` `code` ``. `prefix` is the text of the line before the caret.
    public static func inlineShortcut(prefix: String, typed: String) -> InlineMatch? {
        let units = Array((prefix + typed).utf16)
        switch typed {
        case "*": return emphasisMatch(units, marker: star, onlyAtWordEdges: false)
        case "_": return emphasisMatch(units, marker: underscore, onlyAtWordEdges: true)
        case "`": return codeMatch(units)
        case "~": return tildeMatch(units, tilde: tilde)
        case "\u{FF5E}": return tildeMatch(units, tilde: fullWidthTilde)
        default: return nil
        }
    }

    private static let star = UInt16(UInt8(ascii: "*"))
    private static let underscore = UInt16(UInt8(ascii: "_"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let tilde = UInt16(UInt8(ascii: "~"))
    private static let fullWidthTilde: UInt16 = 0xFF5E

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0xA0 || unit == 0x3000
    }

    private static func hasTrimmedContent(_ units: [UInt16], _ range: Range<Int>) -> Bool {
        !range.isEmpty && !isSpace(units[range.lowerBound]) && !isSpace(units[range.upperBound - 1])
    }

    /// A letter or digit, which an underscore inside a word sits between.
    private static func isWordCharacter(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// `**bold**` and `*italic*`, or with underscores. An underscore only opens at the start
    /// of a word, as in Markdown, so snake_case stays as typed.
    private static func emphasisMatch(_ units: [UInt16], marker: UInt16, onlyAtWordEdges: Bool) -> InlineMatch? {
        let count = units.count
        guard count >= 3 else { return nil }
        func opensHere(_ index: Int) -> Bool {
            !onlyAtWordEdges || index == 0 || !isWordCharacter(units[index - 1])
        }
        if units[count - 2] == marker {
            // Closing pair: the nearest opening pair decides.
            var index = count - 4
            while index >= 0 {
                if units[index] == marker, units[index + 1] == marker, index == 0 || units[index - 1] != marker, opensHere(index) {
                    let content = (index + 2)..<(count - 2)
                    guard hasTrimmedContent(units, content) else { return nil }
                    return InlineMatch(range: index..<count, content: content, style: .bold)
                }
                index -= 1
            }
            return nil
        }
        // Closing single: the nearest marker must be a single one, or the user is still typing
        // a pair.
        var index = count - 3
        while index >= 0 {
            if units[index] == marker {
                guard index == 0 || units[index - 1] != marker, units[index + 1] != marker else { return nil }
                if opensHere(index) {
                    let content = (index + 1)..<(count - 1)
                    guard hasTrimmedContent(units, content) else { return nil }
                    return InlineMatch(range: index..<count, content: content, style: .italic)
                }
            }
            index -= 1
        }
        return nil
    }

    private static func codeMatch(_ units: [UInt16]) -> InlineMatch? {
        let count = units.count
        guard count >= 3, units[count - 2] != backtick else { return nil }
        var index = count - 2
        while index >= 0 {
            if units[index] == backtick {
                guard index == 0 || units[index - 1] != backtick else { return nil }
                let content = (index + 1)..<(count - 1)
                guard units[content].contains(where: { !isSpace($0) }) else { return nil }
                return InlineMatch(range: index..<count, content: content, style: .code)
            }
            index -= 1
        }
        return nil
    }

    private static func tildeMatch(_ units: [UInt16], tilde: UInt16) -> InlineMatch? {
        let count = units.count
        guard count >= 5, units[count - 2] == tilde else { return nil }
        var index = count - 4
        while index >= 0 {
            if units[index] == tilde, units[index + 1] == tilde, index == 0 || units[index - 1] != tilde {
                let content = (index + 2)..<(count - 2)
                guard hasTrimmedContent(units, content) else { return nil }
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
