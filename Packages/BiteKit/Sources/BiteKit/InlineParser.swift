import Foundation

/// Parses the inline part of a line: `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``,
/// `[links](https://example.com)` and backslash escapes. `__bold__` and `_italic_` are read too,
/// as other apps write them, but never written. An image, `![text](a.png)`, stays as written.
///
/// This follows CommonMark's delimiter-run algorithm, but decides whether a run can open or
/// close by whitespace alone. CommonMark's extra punctuation rule rejects things people type
/// all the time, like `**Note:**next` or `**(draft)**text`, so it's left out.
enum InlineParser {
    private enum Token {
        case text(String)
        case code(String)
        case delimiter(Delimiter)
        /// A link's text, already read, and where it goes.
        case link([InlineRun], String)
    }

    private struct Delimiter {
        let character: Character
        let originalCount: Int
        var count: Int
        let canOpen: Bool
        let canClose: Bool
    }

    private struct Match {
        let opener: Int
        let closer: Int
        let style: InlineStyle
    }

    static func parse(_ text: some StringProtocol) -> [InlineRun] {
        var tokens = tokenize(Array(text))
        let matches = matchDelimiters(&tokens)
        // Each pair styles the tokens between its markers. Counting pairs in and out as the
        // tokens go by keeps a long line linear: checking every pair for every token took
        // seconds for a line of a few hundred thousand characters.
        var entering = [[InlineStyle]](repeating: [], count: tokens.count + 1)
        var leaving = [[InlineStyle]](repeating: [], count: tokens.count + 1)
        for match in matches where match.closer - match.opener > 1 {
            entering[match.opener + 1].append(match.style)
            leaving[match.closer].append(match.style)
        }
        var depth: [InlineStyle: Int] = [:]
        var runs: [InlineRun] = []
        for (index, token) in tokens.enumerated() {
            for style in leaving[index] { depth[style, default: 0] -= 1 }
            for style in entering[index] { depth[style, default: 0] += 1 }
            var style: InlineStyle = []
            for (option, count) in depth where count > 0 {
                style.insert(option)
            }
            switch token {
            case .text(let string):
                runs.append(InlineRun(string, style: style))
            case .code(let string):
                runs.append(InlineRun(string, style: style.union(.code)))
            case .link(let text, let destination):
                for run in text {
                    runs.append(InlineRun(run.text, style: style.union(run.style), link: destination))
                }
            case .delimiter(let delimiter):
                // Whatever wasn't used for emphasis is literal text.
                if delimiter.count > 0 {
                    runs.append(InlineRun(String(repeating: delimiter.character, count: delimiter.count), style: style))
                }
            }
        }
        return InlineRun.normalized(plainAddresses(in: runs))
    }

    /// Stand-ins, while a line is read, for the `:`, `.` or `@` escaped in an address kept from
    /// being a link, `https\://a.b`, `www\.a.b` or `name\@a.b`.
    private static let colonMark = LinkDetector.colonStandIn, dotMark = LinkDetector.dotStandIn
    private static let atMark = LinkDetector.atStandIn

    /// The stand-in for `character`, escaped right after `text`, if it's where an address is kept
    /// from being a link: a `:` after a scheme, or a `.` after `www`, at the start of a word, or
    /// an `@` after an email address's name.
    private static func plainAddressMark(for character: Character, after text: String) -> Character? {
        if character == "@" {
            guard let last = text.last, last.isASCII, last.isLetter || last.isNumber || "._+-".contains(last) else { return nil }
            return atMark
        }
        let prefixes: [String] = character == ":" ? ["https", "http"] : character == "." ? ["www"] : []
        for prefix in prefixes where text.lowercased().hasSuffix(prefix) {
            let before = text.dropLast(prefix.count).last
            guard before.map({ !($0.isASCII && ($0.isLetter || $0.isNumber)) }) ?? true else { return nil }
            return character == ":" ? colonMark : dotMark
        }
        return nil
    }

    /// Addresses kept from being links, as read: text again, with an empty link, which a page shows
    /// as text, where the address would have shown as one.
    private static func plainAddresses(in runs: [InlineRun]) -> [InlineRun] {
        let standIns: [UInt16: UInt16] = [0xFDD0: UInt16(UInt8(ascii: ":")), 0xFDD1: UInt16(UInt8(ascii: ".")),
                                          0xFDD2: UInt16(UInt8(ascii: "@"))]
        guard runs.contains(where: { $0.text.contains(colonMark) || $0.text.contains(dotMark) || $0.text.contains(atMark) }) else {
            return runs
        }
        var result: [InlineRun] = []
        for run in runs {
            let marked = Array(run.text.utf16)
            let marks = Set(marked.indices.filter { standIns[marked[$0]] != nil })
            guard !marks.isEmpty else {
                result.append(run)
                continue
            }
            let units = marked.map { standIns[$0] ?? $0 }
            let text = String(decoding: units, as: UTF16.self)
            // In a link's own text, it's the link's.
            guard run.link == nil else {
                result.append(InlineRun(text, style: run.style, link: run.link))
                continue
            }
            var position = 0
            for address in LinkDetector.addresses(in: text) where marks.contains(LinkDetector.escapeOffset(ofAddressAt: address, in: units)) {
                if address.lowerBound > position {
                    result.append(InlineRun(String(decoding: units[position..<address.lowerBound], as: UTF16.self), style: run.style))
                }
                result.append(InlineRun(String(decoding: units[address], as: UTF16.self), style: run.style, link: ""))
                position = address.upperBound
            }
            if position < units.count {
                result.append(InlineRun(String(decoding: units[position...], as: UTF16.self), style: run.style))
            }
        }
        return result
    }

    private static func tokenize(_ characters: [Character]) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        // Backtick run lengths with no closing run left after some point: a later run of the
        // same length can't find one either, so it isn't searched for again.
        var unclosedLengths: Set<Int> = []
        let closingBrackets = closingBrackets(in: characters)
        // Where a backslash made the character after it text, which a `!` then isn't an image's.
        var escaped = -1
        func flush() {
            if !buffer.isEmpty {
                tokens.append(.text(buffer))
                buffer = ""
            }
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1].isASCIIPunctuation {
                buffer.append(plainAddressMark(for: characters[index + 1], after: buffer) ?? characters[index + 1])
                escaped = index + 1
                index += 2
                continue
            }
            if character == "`" {
                let length = runLength(of: "`", in: characters, from: index)
                if !unclosedLengths.contains(length),
                   let close = closingBacktickRun(length: length, in: characters, from: index + length) {
                    flush()
                    tokens.append(.code(codeContent(characters[(index + length)..<close])))
                    index = close + length
                } else {
                    unclosedLengths.insert(length)
                    buffer += String(repeating: "`", count: length)
                    index += length
                }
                continue
            }
            let isImage = index > 0 && characters[index - 1] == "!" && escaped != index - 1
            if character == "[", !isImage, let link = link(in: characters, from: index, closingBracket: closingBrackets[index]) {
                flush()
                tokens.append(.link(link.text, link.destination))
                index = link.end
                continue
            }
            if character == "*" || character == "_" || character == "~" {
                let length = runLength(of: character, in: characters, from: index)
                if character == "~", length < 2 {
                    buffer.append(character)
                    index += 1
                    continue
                }
                let before = index > 0 ? characters[index - 1] : nil
                let after = index + length < characters.count ? characters[index + length] : nil
                var canOpen = after.map { !$0.isWhitespace } ?? false
                var canClose = before.map { !$0.isWhitespace } ?? false
                if character == "_" {
                    // Underscores inside a word are just underscores, as in snake_case.
                    canOpen = canOpen && !(before?.isLetterOrNumber ?? false)
                    canClose = canClose && !(after?.isLetterOrNumber ?? false)
                }
                flush()
                tokens.append(.delimiter(Delimiter(
                    character: character,
                    originalCount: length,
                    count: length,
                    canOpen: canOpen,
                    canClose: canClose
                )))
                index += length
                continue
            }
            buffer.append(character)
            index += 1
        }
        flush()
        return tokens
    }

    /// The `]` that closes each `[`, by position, over the whole line at once, as brackets nest.
    /// Escaped brackets and those in code don't count. Searching from each `[` in turn went over
    /// the rest of the line again for every one of them.
    private static func closingBrackets(in characters: [Character]) -> [Int: Int] {
        guard characters.contains("[") else { return [:] }
        var closing: [Int: Int] = [:]
        var open: [Int] = []
        var unclosedLengths: Set<Int> = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1].isASCIIPunctuation {
                index += 2
                continue
            }
            if character == "`" {
                let length = runLength(of: "`", in: characters, from: index)
                if !unclosedLengths.contains(length), let close = closingBacktickRun(length: length, in: characters, from: index + length) {
                    index = close + length
                } else {
                    unclosedLengths.insert(length)
                    index += length
                }
                continue
            }
            if character == "[" {
                open.append(index)
            } else if character == "]", let opener = open.popLast() {
                closing[opener] = index
            }
            index += 1
        }
        return closing
    }

    /// The link starting at the `[` at `start`, if there is one: `[text](destination)`, the
    /// destination maybe in angle brackets. A link can't hold another, so with one inside, the
    /// inner one is the link. Without text or a destination, it's only text.
    private static func link(in characters: [Character], from start: Int, closingBracket: Int?)
        -> (text: [InlineRun], destination: String, end: Int)? {
        guard let close = closingBracket, close > start + 1, close + 1 < characters.count, characters[close + 1] == "(",
              let destination = linkDestination(in: characters, from: close + 2) else { return nil }
        let text = parse(String(characters[(start + 1)..<close]))
        guard !text.isEmpty, !text.contains(where: { $0.link != nil }) else { return nil }
        return (text, destination.text, destination.end)
    }

    /// A link's destination, starting just after its `(`, and where the link ends, past its `)`.
    /// Spaces may stand around it, and a title after it, as other apps write one: `"title"`,
    /// `'title'` or `(title)`. A title shows nowhere in Bite, and goes.
    private static func linkDestination(in characters: [Character], from start: Int) -> (text: String, end: Int)? {
        var index = start
        var destination = ""
        /// The character a backslash before it stands for, taking both.
        func escaped() -> Character? {
            guard characters[index] == "\\", index + 1 < characters.count, characters[index + 1].isASCIIPunctuation else { return nil }
            index += 2
            return characters[index - 1]
        }
        func skipSpaces() {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        }
        skipSpaces()
        if index < characters.count, characters[index] == "<" {
            index += 1
            while index < characters.count, characters[index] != ">" {
                if let character = escaped() {
                    destination.append(character)
                    continue
                }
                guard characters[index] != "<" else { return nil }
                destination.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
        } else {
            // Brackets in it pair up, as in a Wikipedia address.
            var depth = 0
            while index < characters.count, !characters[index].isWhitespace {
                if let character = escaped() {
                    destination.append(character)
                    continue
                }
                if characters[index] == "(" { depth += 1 }
                if characters[index] == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                destination.append(characters[index])
                index += 1
            }
        }
        let destinationEnd = index
        skipSpaces()
        if index > destinationEnd, index < characters.count, let closer = titleClosers[characters[index]] {
            index += 1
            while index < characters.count, characters[index] != closer {
                if escaped() != nil { continue }
                // A title in brackets holds no bracket of its own.
                guard closer != ")" || characters[index] != "(" else { return nil }
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
            skipSpaces()
        }
        guard !destination.isEmpty, index < characters.count, characters[index] == ")" else { return nil }
        return (destination, index + 1)
    }

    private static let titleClosers: [Character: Character] = ["\"": "\"", "'": "'", "(": ")"]

    private static func runLength(of character: Character, in characters: [Character], from start: Int) -> Int {
        var end = start
        while end < characters.count, characters[end] == character {
            end += 1
        }
        return end - start
    }

    private static func closingBacktickRun(length: Int, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == "`" {
                let run = runLength(of: "`", in: characters, from: index)
                if run == length { return index }
                index += run
            } else {
                index += 1
            }
        }
        return nil
    }

    /// One space on each side is padding (used when the code itself starts or ends with a backtick).
    private static func codeContent(_ characters: ArraySlice<Character>) -> String {
        let content = String(characters)
        if content.count >= 2, content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
            return String(content.dropFirst().dropLast())
        }
        return content
    }

    /// CommonMark's delimiter matching, with its stack of possible openers and its
    /// `openers_bottom`: once no opener was found for a kind of closer, later ones of that kind
    /// stop looking where it stopped. Going back through the whole line for each closer, and
    /// marking everything between each pair, made a long line quadratic.
    private static func matchDelimiters(_ tokens: inout [Token]) -> [Match] {
        struct Kind: Hashable {
            let character: Character
            let canOpen: Bool
            let lengthModThree: Int
        }
        var matches: [Match] = []
        // Token indices of delimiters that may still open, in order.
        var openers: [Int] = []
        // How far down `openers` a closer of each kind still needs to look.
        var bottoms: [Kind: Int] = [:]
        func popOpeners(to height: Int) {
            openers.removeSubrange(height...)
            for (kind, bottom) in bottoms where bottom > height {
                bottoms[kind] = height
            }
        }
        for closerIndex in tokens.indices {
            guard case .delimiter(var closer) = tokens[closerIndex] else { continue }
            if closer.canClose {
                let kind = Kind(character: closer.character, canOpen: closer.canOpen, lengthModThree: closer.originalCount % 3)
                while closer.count > 0 {
                    // What's left of a tilde run is too short to strike anything through. It
                    // mustn't count as a search that failed, which would stop longer runs.
                    if closer.character == "~", closer.count < 2 { break }
                    var position = openers.count - 1
                    let bottom = min(bottoms[kind] ?? 0, openers.count)
                    var found: Int?
                    while position >= bottom {
                        if case .delimiter(let opener) = tokens[openers[position]], canPair(opener, closer) {
                            found = position
                            break
                        }
                        position -= 1
                    }
                    guard let foundPosition = found, case .delimiter(var opener) = tokens[openers[foundPosition]] else {
                        bottoms[kind] = openers.count
                        break
                    }
                    let openerIndex = openers[foundPosition]
                    let used = closer.character == "~" ? 2 : (opener.count >= 2 && closer.count >= 2 ? 2 : 1)
                    let style: InlineStyle = closer.character == "~" ? .strikethrough : (used == 2 ? .bold : .italic)
                    opener.count -= used
                    closer.count -= used
                    tokens[openerIndex] = .delimiter(opener)
                    matches.append(Match(opener: openerIndex, closer: closerIndex, style: style))
                    // Emphasis can't cross: anything left between the pair is literal.
                    popOpeners(to: foundPosition + 1)
                    if opener.count == 0 { popOpeners(to: foundPosition) }
                }
            }
            tokens[closerIndex] = .delimiter(closer)
            if closer.canOpen, closer.count > 0 {
                openers.append(closerIndex)
            }
        }
        return matches
    }

    private static func canPair(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
        guard opener.canOpen, opener.count > 0, opener.character == closer.character else { return false }
        if closer.character == "~" { return opener.count >= 2 && closer.count >= 2 }
        // CommonMark's "rule of three", needed to read `**a*b***` correctly.
        let eitherBoth = opener.canClose || closer.canOpen
        let sum = opener.originalCount + closer.originalCount
        let bothMultiples = opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0
        return !(eitherBoth && sum % 3 == 0 && !bothMultiples)
    }
}

extension Character {
    var isLetterOrNumber: Bool {
        isLetter || isNumber
    }

    var isASCIIPunctuation: Bool {
        guard isASCII, let value = unicodeScalars.first?.value else { return false }
        return (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value) || (123...126).contains(value)
    }
}
