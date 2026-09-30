/// How an ordered list's numbers are written. Lists in digits have none.
public enum NumberStyle: String, Sendable, Hashable, CaseIterable {
    case letters, capitalLetters, roman, capitalRoman
}

public enum ListNumbering {
    public struct Number: Equatable, Sendable {
        public var ordinal: Int
        /// The style of the item the list started with.
        public var style: NumberStyle?
    }

    /// The number shown in front of each ordered item, and how it's written, or nil for every
    /// other block.
    ///
    /// Numbering restarts after any block that isn't a list, and a bullet or to-do at the
    /// same level interrupts it. Going back up a level forgets the deeper counters. A list
    /// starts at the number written on its first item (`3.`), or at 1, and takes its style.
    /// An item in another style starts a list of its own, so `I.` typed right after a lettered
    /// list begins a Roman one. An item in digits, or in no style of its own, carries on.
    public static func numbers(for items: [(kind: BlockKind, indent: Int, number: Int?, style: NumberStyle?)]) -> [Number?] {
        // The last number used at each level, or nil where no numbered list is running.
        var counters: [Number?] = []
        return items.map { item in
            guard item.kind.isList else {
                counters.removeAll()
                return nil
            }
            let level = max(0, item.indent)
            if counters.count > level + 1 {
                counters.removeLast(counters.count - level - 1)
            }
            while counters.count < level + 1 {
                counters.append(nil)
            }
            guard item.kind == .ordered else {
                counters[level] = nil
                return nil
            }
            let number = next(after: counters[level], number: item.number, style: item.style)
            counters[level] = number
            return number
        }
    }

    /// For each ordered item, the index of the item its list starts with; nil for other blocks.
    public static func firstItems(for items: [(kind: BlockKind, indent: Int, style: NumberStyle?)]) -> [Int?] {
        let numbers = numbers(for: items.map { ($0.kind, $0.indent, nil, $0.style) })
        var starts: [Int: Int] = [:]
        return items.indices.map { index in
            guard let number = numbers[index] else { return nil }
            let level = max(0, items[index].indent)
            if number.ordinal == 1 { starts[level] = index }
            return starts[level]
        }
    }

    /// The number of an ordered item that follows `running` at its level (nil where no list is
    /// running there).
    static func next(after running: Number?, number: Int?, style: NumberStyle?) -> Number {
        if let running, style == nil || style == running.style {
            return Number(ordinal: running.ordinal + 1, style: running.style)
        }
        return Number(ordinal: number ?? 1, style: style)
    }

    public static func ordinals(for items: [(kind: BlockKind, indent: Int, number: Int?)]) -> [Int?] {
        numbers(for: items.map { ($0.kind, $0.indent, $0.number, nil) }).map { $0?.ordinal }
    }

    public static func ordinals(for items: [(kind: BlockKind, indent: Int)]) -> [Int?] {
        ordinals(for: items.map { ($0.kind, $0.indent, nil) })
    }

    /// True for each ordered item that starts a list, where a written number takes effect.
    public static func startsList(_ items: [(kind: BlockKind, indent: Int)]) -> [Bool] {
        startsList(items.map { ($0.kind, $0.indent, nil) })
    }

    public static func startsList(_ items: [(kind: BlockKind, indent: Int, style: NumberStyle?)]) -> [Bool] {
        numbers(for: items.map { ($0.kind, $0.indent, nil, $0.style) }).map { $0?.ordinal == 1 }
    }

    /// A marker that's a single letter reads as a letter, or as a Roman numeral for i. In a
    /// list of the other kind it may be that list's next item instead: v after iv, i after h.
    /// Returns what the item reads as in `running`, if it carries that list on.
    static func reading(number: Int, style: NumberStyle, asNextIn running: Number) -> Number? {
        guard let other = running.style, other != style,
              let written = written(number, in: style), written.count == 1,
              let reread = value(ofMarker: written, as: other), reread == running.ordinal + 1 else { return nil }
        return Number(ordinal: reread, style: other)
    }

    /// The value of a marker read in the given style, if it can be.
    static func value(ofMarker text: String, as style: NumberStyle) -> Int? {
        let isCapital = text.allSatisfy(\.isUppercase)
        guard isCapital == (style == .capitalLetters || style == .capitalRoman) else { return nil }
        let lower = text.lowercased()
        switch style {
        case .letters, .capitalLetters:
            guard lower.count == 1, let scalar = lower.unicodeScalars.first, ("a"..."z").contains(scalar) else { return nil }
            return Int(scalar.value) - 96
        case .roman, .capitalRoman:
            return romanValue(lower)
        }
    }

    /// How an ordered item's number reads. In a list written in digits it goes by the level:
    /// 1. at the top, a. one level in and i. the next, then round again, as in Notion; Markdown
    /// keeps the digits. A list started with a letter or Roman numeral keeps to that style at
    /// any level. A list can start at 0, which only digits can show.
    public static func label(for ordinal: Int, indent: Int, style: NumberStyle? = nil) -> String {
        let number = max(0, ordinal)
        let style = style ?? [nil, .letters, .roman][max(0, indent) % 3]
        return (style.flatMap { written(number, in: $0) } ?? String(number)) + "."
    }

    /// The number in letters or Roman numerals, or nil if it can't be written that way.
    static func written(_ number: Int, in style: NumberStyle) -> String? {
        guard number > 0 else { return nil }
        return switch style {
        case .letters: letters(number)
        case .capitalLetters: letters(number).uppercased()
        case .roman: roman(number)
        case .capitalRoman: roman(number)?.uppercased()
        }
    }

    /// The marker Markdown gets for an ordered item. Where letters or a Roman numeral wouldn't
    /// read back, it's written in digits: letters beyond z, and where a list starts, a marker
    /// that reads as the other style (a lettered list starting at i, a Roman one at v or x).
    /// The number is kept. Only a list's first item says the style, so later items in digits
    /// still read back in it.
    static func marker(for ordinal: Int, style: NumberStyle?, startsList: Bool) -> String {
        guard let style, let written = written(ordinal, in: style), let value = value(ofMarker: written),
              !startsList || (value.number == ordinal && value.style == style) else { return "\(ordinal)." }
        return written + "."
    }

    /// The value of a letter or Roman numeral marker: a single letter, or a Roman numeral all in
    /// small letters or all in capitals. A lone i reads as Roman, as in Pandoc.
    public static func value(ofMarker text: some StringProtocol) -> (number: Int, style: NumberStyle)? {
        guard !text.isEmpty, text.count <= 15, text.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let isCapital = text.allSatisfy(\.isUppercase)
        guard isCapital || text.allSatisfy(\.isLowercase) else { return nil }
        let lower = text.lowercased()
        if lower.count == 1, lower != "i", let scalar = lower.unicodeScalars.first {
            return (Int(scalar.value) - 96, isCapital ? .capitalLetters : .letters)
        }
        guard let number = romanValue(lower) else { return nil }
        return (number, isCapital ? .capitalRoman : .roman)
    }

    /// The value of a Roman numeral in its usual form (so not iiii or ic), up to 3999.
    static func romanValue(_ text: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        var total = 0
        var previous = 0
        for character in text.reversed() {
            guard let value = values[character] else { return nil }
            total += value < previous ? -value : value
            previous = max(previous, value)
        }
        guard (1...3999).contains(total), roman(total) == text else { return nil }
        return total
    }

    /// a … z, then aa, ab and so on.
    static func letters(_ number: Int) -> String {
        var remaining = number
        var result = ""
        while remaining > 0 {
            remaining -= 1
            result = String(UnicodeScalar(UInt8(97 + remaining % 26))) + result
            remaining /= 26
        }
        return result
    }

    /// Lowercase Roman numerals, up to 3999.
    static func roman(_ number: Int) -> String? {
        guard (1...3999).contains(number) else { return nil }
        let values = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                      (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var remaining = number
        var result = ""
        for (value, numeral) in values {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }
}
