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
        var isActive = true
    }

    private struct Match {
        let opener: Int
        let closer: Int
        let style: InlineStyle
    }

    static func parse(_ text: some StringProtocol) -> [InlineRun] {
        var tokens = tokenize(Array(text))
        let matches = matchDelimiters(&tokens)
        var runs: [InlineRun] = []
        for (index, token) in tokens.enumerated() {
            var style: InlineStyle = []
            for match in matches where match.opener < index && index < match.closer {
                style.insert(match.style)
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
                if let close = closingBacktickRun(length: length, in: characters, from: index + length) {
                    flush()
                    tokens.append(.code(codeContent(characters[(index + length)..<close])))
                    index = close + length
                } else {
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

    private static func matchDelimiters(_ tokens: inout [Token]) -> [Match] {
        var matches: [Match] = []
        for closerIndex in tokens.indices {
            guard case .delimiter(var closer) = tokens[closerIndex], closer.canClose, closer.isActive else { continue }
            while closer.count > 0 {
                guard let openerIndex = opener(for: closer, before: closerIndex, in: tokens),
                      case .delimiter(var opener) = tokens[openerIndex] else { break }
                let used = closer.character == "~" ? 2 : (opener.count >= 2 && closer.count >= 2 ? 2 : 1)
                let style: InlineStyle = closer.character == "~" ? .strikethrough : (used == 2 ? .bold : .italic)
                opener.count -= used
                closer.count -= used
                tokens[openerIndex] = .delimiter(opener)
                matches.append(Match(opener: openerIndex, closer: closerIndex, style: style))
                // Emphasis can't cross: anything left between the pair is literal.
                for between in (openerIndex + 1)..<closerIndex {
                    if case .delimiter(var inner) = tokens[between] {
                        inner.isActive = false
                        tokens[between] = .delimiter(inner)
                    }
                }
            }
            tokens[closerIndex] = .delimiter(closer)
        }
        return matches
    }

    private static func opener(for closer: Delimiter, before closerIndex: Int, in tokens: [Token]) -> Int? {
        var index = closerIndex - 1
        while index >= 0 {
            if case .delimiter(let opener) = tokens[index], opener.isActive, opener.canOpen, opener.count > 0,
               opener.character == closer.character {
                if closer.character == "~" {
                    if opener.count >= 2, closer.count >= 2 { return index }
                } else {
                    // CommonMark's "rule of three", needed to read `**a*b***` correctly.
                    let eitherBoth = opener.canClose || closer.canOpen
                    let sum = opener.originalCount + closer.originalCount
                    let bothMultiples = opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0
                    if !(eitherBoth && sum % 3 == 0 && !bothMultiples) { return index }
                }
            }
            index -= 1
        }
        return nil
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
