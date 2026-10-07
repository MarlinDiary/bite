import Foundation

/// A page as numbered lines, as the command line tool shows and changes it: the lines of its
/// Markdown, counted from 1. Bite writes each line on the page as a line of Markdown, and a code
/// block's fences each as one more; an empty page has none.
public struct PageLines: Equatable, Sendable {
    public var lines: [String]

    public init(_ markdown: String) {
        let text = Self.unixLines(markdown)
        // Empty as Bite counts it: nothing but line breaks.
        guard text.contains(where: { $0 != "\n" && $0 != "\u{FEFF}" }) else {
            lines = []
            return
        }
        lines = Self.split(text)
    }

    public init(lines: [String]) {
        self.lines = lines
    }

    /// Text given to go on a page, a line of the page for each of its lines: a last line break ends
    /// the last line, as in a file.
    public static func given(_ text: String) -> [String] {
        split(unixLines(text))
    }

    private static func unixLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func split(_ text: String) -> [String] {
        var text = Substring(text)
        if text.hasSuffix("\n") { text = text.dropLast() }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The Markdown, each line ended, as Bite writes it.
    public var markdown: String {
        lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    public var count: Int {
        lines.count
    }

    /// A short name for the page as it is, which any change to it changes: a change made "if the
    /// page is still as read" names the version read.
    public static func version(of markdown: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in markdown.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String((String(repeating: "0", count: max(0, 16 - hex.count)) + hex).prefix(8))
    }

    /// The lines numbered from 1, the numbers lined up.
    public func numbered() -> String {
        let width = String(count).count
        return lines.enumerated().map { index, line in
            let number = String(index + 1)
            return String(repeating: " ", count: width - number.count) + number + "  " + line
        }.joined(separator: "\n")
    }

    // MARK: Finding

    /// The lines that say `query`, as numbers: whatever its capitals and accents.
    public func lines(saying query: String) -> [Int] {
        lines.indices.filter { lines[$0].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.map { $0 + 1 }
    }

    /// A to-do's box: what comes before it, and whether it's ticked.
    private static var toDo: Regex<(Substring, Substring, Substring, Substring, Substring)> {
        /^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])(.*)$/
    }

    /// Whether line `number` is a to-do, ticked or not, and what it says.
    public func toDo(at number: Int) -> (done: Bool, text: String)? {
        guard lines.indices.contains(number - 1), let match = lines[number - 1].wholeMatch(of: Self.toDo) else { return nil }
        return (match.output.2 != " ", match.output.4.trimmingCharacters(in: .whitespaces))
    }

    /// The page's to-dos, in order: each one's line, whether it's ticked off, and what it says.
    public var toDos: [(line: Int, done: Bool, text: String)] {
        lines.indices.compactMap { index in toDo(at: index + 1).map { (index + 1, $0.done, $0.text) } }
    }

    /// The to-do that says `text`: the one saying just that, whatever its capitals, or else the one
    /// line saying it among others. `page` names the page in what's said when there's none, or more
    /// than one.
    public func toDo(saying text: String, page: String) throws -> Int {
        let toDos = lines.indices.map { $0 + 1 }.compactMap { number in toDo(at: number).map { (number, $0.text) } }
        let wanted = text.trimmingCharacters(in: .whitespaces)
        let exact = toDos.filter { $0.1.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        let found = exact.isEmpty ? toDos.filter { $0.1.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) != nil } : exact
        guard let first = found.first else { throw CommandError("No to-do on the \(page) page says \"\(wanted)\".") }
        guard found.count == 1 else {
            throw CommandError("\(found.count) to-dos on the \(page) page say \"\(wanted)\", on lines \(found.map { String($0.0) }.joined(separator: ", ")): name one by its line.")
        }
        return first.0
    }

    // MARK: Changing

    /// Checks that `range` is lines on the page, which `page` names in what's said if not.
    public func check(_ range: LineRange, page: String) throws {
        guard range.first >= 1, range.first <= range.last else { throw CommandError("\(range) isn't a run of lines: lines are counted from 1.") }
        guard range.last <= count else {
            throw CommandError(count == 0 ? "The \(page) page is empty: it has no line \(range.last)."
                : "The \(page) page has \(count) line\(count == 1 ? "" : "s"): there's no line \(range.last).")
        }
    }

    /// Puts `new` after the first `position` lines: at the start for 0, at the end for `count`.
    public mutating func insert(_ new: [String], at position: Int) {
        lines.insert(contentsOf: new, at: min(max(position, 0), count))
    }

    public mutating func replace(_ range: LineRange, with new: [String]) {
        lines.replaceSubrange(range.first - 1 ... range.last - 1, with: new)
    }

    @discardableResult
    public mutating func remove(_ range: LineRange) -> [String] {
        let removed = Array(lines[range.first - 1 ... range.last - 1])
        lines.removeSubrange(range.first - 1 ... range.last - 1)
        return removed
    }

    /// Moves lines to after the first `position` lines as they are now. `page` names the page in
    /// what's said when that's among the lines moved.
    public mutating func move(_ range: LineRange, to position: Int, page: String) throws {
        if position > range.first - 1, position < range.last {
            throw CommandError("Lines \(range.first) to \(range.last) on the \(page) page can't go in among themselves.")
        }
        let moved = remove(range)
        let position = position >= range.last ? position - moved.count : position
        insert(moved, at: position)
    }

    /// Ticks the to-do on line `number` off, or on again, saying whether it changed. `page` names
    /// the page in what's said when that line isn't a to-do.
    @discardableResult
    public mutating func setToDo(at number: Int, done: Bool, page: String) throws -> Bool {
        guard lines.indices.contains(number - 1), let match = lines[number - 1].wholeMatch(of: Self.toDo) else {
            throw CommandError("Line \(number) on the \(page) page isn't a to-do.")
        }
        guard (match.output.2 != " ") != done else { return false }
        lines[number - 1] = String(match.output.1) + (done ? "x" : " ") + String(match.output.3) + String(match.output.4)
        return true
    }

    /// Replaces `find`, once on the page or, `all`, wherever it is, saying how many times. Text
    /// over more than one line is found across them. `page` names the page in what's said when it
    /// isn't found, or is found more than once and not `all`.
    @discardableResult
    public mutating func replaceText(_ find: String, with replacement: String, all: Bool, page: String) throws -> Int {
        guard !find.isEmpty else { throw CommandError("Say what text to find.") }
        let find = Self.unixLines(find)
        let text = lines.joined(separator: "\n")
        let found = text.components(separatedBy: find).count - 1
        guard found > 0 else { throw CommandError("\"\(find)\" isn't on the \(page) page.") }
        guard found == 1 || all else {
            throw CommandError("\"\(find)\" is on the \(page) page \(found) times: change them all, or give more of the text around the one to change.")
        }
        let changed = text.replacingOccurrences(of: find, with: Self.unixLines(replacement))
        lines = changed.isEmpty ? [] : changed.components(separatedBy: "\n")
        return found
    }
}

/// Lines on a page, from the first to the last, counting from 1.
public struct LineRange: Equatable, Sendable, CustomStringConvertible {
    public var first: Int
    public var last: Int

    public init(_ first: Int, _ last: Int? = nil) {
        self.first = first
        self.last = last ?? first
    }

    /// "3", or "3-5", "3..5" or "3:5".
    public init(parsing text: String) throws {
        let parts = text.replacingOccurrences(of: "..", with: "-").replacingOccurrences(of: ":", with: "-")
            .split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard (1...2).contains(parts.count), let first = parts.first ?? nil, let last = parts.last ?? nil else {
            throw CommandError("\"\(text)\" isn't a line, or lines: give a line's number, or two, as 3-5.")
        }
        self.init(first, last)
    }

    public var description: String {
        first == last ? "line \(first)" : "lines \(first) to \(last)"
    }
}

/// Where lines go on a page.
public enum LinePosition: Equatable, Sendable {
    case start
    case end
    case after(Int)
    case before(Int)

    /// How many lines go before them, on a page of `count` lines, which `page` names in what's said
    /// when that's past the page's end.
    func position(on count: Int, page: String) throws -> Int {
        let position = switch self {
        case .start: 0
        case .end: count
        case .after(let line): line
        case .before(let line): line - 1
        }
        guard (0...count).contains(position) else {
            throw CommandError("The \(page) page has \(count) line\(count == 1 ? "" : "s"): there's no putting lines \(self) there.")
        }
        return position
    }
}

extension LinePosition: CustomStringConvertible {
    public var description: String {
        switch self {
        case .start: "at the start"
        case .end: "at the end"
        case .after(let line): "after line \(line)"
        case .before(let line): "before line \(line)"
        }
    }
}
