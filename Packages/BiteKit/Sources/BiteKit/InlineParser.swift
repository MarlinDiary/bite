import Foundation

/// Parses the inline part of a line: `**bold**`, `*italic*`, `~~strike~~`, `` `code` `` and
/// backslash escapes. `__bold__` and `_italic_` are read too, as other apps write them, but
/// never written.
///
/// This follows CommonMark's delimiter-run algorithm, but decides whether a run can open or
/// close by whitespace alone. CommonMark's extra punctuation rule rejects things people type
/// all the time, like `**Note:**next` or `**(draft)**text`, so it's left out.
enum InlineParser {
    private enum Token {
        case text(String)
        case code(String)
        case delimiter(Delimiter)
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
            case .delimiter(let delimiter):
                // Whatever wasn't used for emphasis is literal text.
                if delimiter.count > 0 {
                    runs.append(InlineRun(String(repeating: delimiter.character, count: delimiter.count), style: style))
                }
            }
        }
        return InlineRun.normalized(runs)
    }

    private static func tokenize(_ characters: [Character]) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        // Backtick run lengths with no closing run left after some point: a later run of the
        // same length can't find one either, so it isn't searched for again.
        var unclosedLengths: Set<Int> = []
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
                buffer.append(characters[index + 1])
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
