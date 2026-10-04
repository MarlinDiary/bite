import Foundation

/// What kind of line a block is. Every line in a dot is one block.
public enum BlockKind: String, Sendable, Hashable, CaseIterable {
    case paragraph
    case heading1
    case heading2
    case heading3
    /// Levels 4 to 6 look like level 3, but keep their level in the Markdown.
    case heading4
    case heading5
    case heading6
    case bullet
    case ordered
    case todo
    case quote
    case code
    case divider

    public var isHeading: Bool {
        headingLevel != nil
    }

    /// 1 for `#`, up to 6 for `######`.
    public var headingLevel: Int? {
        switch self {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        case .heading4: 4
        case .heading5: 5
        case .heading6: 6
        default: nil
        }
    }

    public static func heading(level: Int) -> BlockKind {
        switch level {
        case ...1: .heading1
        case 2: .heading2
        case 3: .heading3
        case 4: .heading4
        case 5: .heading5
        default: .heading6
        }
    }

    /// Lists can nest (see `Block.indent`).
    public var isList: Bool {
        self == .bullet || self == .ordered || self == .todo
    }
}

/// Inline formatting applied to a run of text.
public struct InlineStyle: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold = InlineStyle(rawValue: 1 << 0)
    public static let italic = InlineStyle(rawValue: 1 << 1)
    public static let strikethrough = InlineStyle(rawValue: 1 << 2)
    public static let code = InlineStyle(rawValue: 1 << 3)
}

public struct InlineRun: Sendable, Hashable {
    public var text: String
    public var style: InlineStyle
    /// Where the text links to, as the Markdown has it: `[text](link)`. Nil for text that isn't
    /// a link. An address written out in the text is no link here, only shown as one. Empty for
    /// an address written out but kept from showing as a link, `www\.example.com` in Markdown.
    public var link: String?

    public init(_ text: String, style: InlineStyle = [], link: String? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }

    /// Drops empty runs and merges neighbours that share a style and a link.
    public static func normalized(_ runs: [InlineRun]) -> [InlineRun] {
        var result: [InlineRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.style == run.style, last.link == run.link {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}

public struct Block: Sendable, Hashable {
    public var kind: BlockKind
    /// Nesting level. Only lists nest; it's always 0 for other kinds.
    public var indent: Int
    /// Only meaningful for `.todo`.
    public var isChecked: Bool
    /// The number written in front of an ordered item. Only the first item of a list counts:
    /// the list starts there. Nil for items that just carry on.
    public var number: Int?
    /// How an ordered list's numbers are written: `a.`, `A.`, `i.` or `I.`. Like the number,
    /// it's taken from the item that starts the list, but every item keeps it, so the next one
    /// takes over if the first goes. Nil for digits, which nested lists show as letters and
    /// Roman numerals in turn.
    public var numberStyle: NumberStyle?
    /// The language named after a code fence (```` ```swift ````), kept on every line of the block.
    public var language: String
    public var runs: [InlineRun]

    public init(kind: BlockKind = .paragraph, indent: Int = 0, isChecked: Bool = false, number: Int? = nil,
                numberStyle: NumberStyle? = nil, language: String = "", runs: [InlineRun] = []) {
        self.kind = kind
        self.indent = kind.isList ? max(0, indent) : 0
        self.isChecked = kind == .todo && isChecked
        self.number = kind == .ordered ? number : nil
        self.numberStyle = kind == .ordered ? numberStyle : nil
        self.language = kind == .code ? language : ""
        self.runs = kind == .divider ? [] : InlineRun.normalized(runs)
    }

    public init(_ kind: BlockKind, _ text: String = "", indent: Int = 0, checked: Bool = false, number: Int? = nil,
                numberStyle: NumberStyle? = nil, language: String = "") {
        self.init(kind: kind, indent: indent, isChecked: checked, number: number, numberStyle: numberStyle,
                  language: language, runs: [InlineRun(text)])
    }

    public var text: String {
        runs.map(\.text).joined()
    }
}

public struct BiteDocument: Sendable, Hashable {
    public var blocks: [Block]

    public init(blocks: [Block] = []) {
        self.blocks = blocks
    }

    /// True when there's nothing but empty paragraphs.
    public var isEmpty: Bool {
        blocks.allSatisfy { $0.kind == .paragraph && $0.text.isEmpty }
    }

    public var plainText: String {
        blocks.map(\.text).joined(separator: "\n")
    }
}
