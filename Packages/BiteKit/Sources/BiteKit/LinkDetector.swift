import Foundation

/// Web addresses written out in text, `https://example.com` or `www.example.com`, and email
/// addresses, `name@example.com`, which a page shows as links though its Markdown has them as
/// plain text, as GitHub's does.
public enum LinkDetector {
    /// Where the addresses in `text` are, as UTF-16 offsets. An address starts with `https://`,
    /// `http://` or `www.`, not right after a letter or digit, and runs to a space. Its site's name
    /// is ASCII, so text in another script right after it isn't the address's. Past the name,
    /// words in any script can be in it, as a search's are, up to a space or punctuation, a full
    /// stop in another script too. Punctuation at its end, a full stop or a comma, isn't part of
    /// it, nor is a closing bracket, round or square, whose opening one is outside, nor words in
    /// another script that don't stand as a part of the path or a value on their own, after a `/`
    /// or an `=`. Email addresses are found too (see `emailAddresses`).
    public static func addresses(in text: String) -> [Range<Int>] {
        let units = Array(text.utf16)
        guard units.count >= 4, text.contains(where: { $0 == "/" || $0 == "." }) else { return [] }
        let web = webAddresses(in: units)
        let emails = emailAddresses(in: units).filter { email in !web.contains { $0.overlaps(email) } }
        return emails.isEmpty ? web : (web + emails).sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func webAddresses(in units: [UInt16]) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var index = 0
        while index < units.count {
            guard let length = prefixLength(in: units, at: index),
                  index == 0 || !isASCIILetterOrDigit(units[index - 1]) else {
                index += 1
                continue
            }
            var end = index + length
            while end < units.count, isAddressUnit(units[end]), !pathStarts.contains(units[end]) {
                end += 1
            }
            if end < units.count, pathStarts.contains(units[end]) {
                while end < units.count {
                    if isAddressUnit(units[end]) {
                        end += 1
                    } else if let wordLength = wordLength(in: units, at: end) {
                        end += wordLength
                    } else {
                        break
                    }
                }
            }
            end = trimmedEnd(units, from: index, to: end)
            if end > index + length {
                found.append(index..<end)
                index = end
            } else {
                index += length
            }
        }
        return found
    }

    /// Where `address`, as written out, goes: one starting with `www.` goes to its secure site, and
    /// an email address is mailed.
    public static func destination(of address: String) -> String {
        let lowered = address.lowercased()
        if lowered.hasPrefix("www.") { return "https://" + address }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || !address.contains("@") { return address }
        return "mailto:" + address
    }

    /// Email addresses written out, as GitHub finds them: a name of letters, digits, `.`, `_`, `+`
    /// or `-`, then an `@`, then a domain of two parts or more, the last one letters, two at least.
    /// A full stop, `-` or `_` at its end is the sentence's.
    private static func emailAddresses(in units: [UInt16]) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var index = 0
        while index < units.count {
            guard units[index] == at else {
                index += 1
                continue
            }
            var start = index
            while start > 0, isEmailNameUnit(units[start - 1]) { start -= 1 }
            while start < index, units[start] == dot { start += 1 }
            var end = index + 1
            while end < units.count, isASCIILetterOrDigit(units[end]) || [dot, hyphen, underscore].contains(units[end]) {
                end += 1
            }
            while end > index + 1, [dot, hyphen, underscore].contains(units[end - 1]) { end -= 1 }
            let labels = units[(index + 1)..<end].split(separator: dot, omittingEmptySubsequences: false)
            if start < index, labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last,
               last.count >= 2, last.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) {
                found.append(start..<end)
                index = end
            } else {
                index += 1
            }
        }
        return found
    }

    private static let at = UInt16(UInt8(ascii: "@")), dot = UInt16(UInt8(ascii: "."))
    private static let hyphen = UInt16(UInt8(ascii: "-")), underscore = UInt16(UInt8(ascii: "_"))

    private static func isEmailNameUnit(_ unit: UInt16) -> Bool {
        isASCIILetterOrDigit(unit) || [dot, hyphen, underscore, UInt16(UInt8(ascii: "+"))].contains(unit)
    }

    /// Where a link to `address`, as typed for one, goes, written in full so that any app opening
    /// the page's Markdown can follow it: an address with no scheme is a web address and goes to its
    /// secure site, and an email address is mailed. Left as typed, `example.com` was a file next to
    /// the page to other apps, and an email address opened as a website.
    public static func destination(forTyped address: String) -> String {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !hasScheme(address), !address.hasPrefix("/"), !address.hasPrefix("#"),
              !address.hasPrefix(".") else { return address }
        return isEmailAddress(address) ? "mailto:" + address : "https://" + address
    }

    /// Whether `address` starts with a scheme, `https:` or `mailto:`, as against a host and its
    /// port, `example.com:8080`.
    private static func hasScheme(_ address: String) -> Bool {
        guard let colon = address.firstIndex(of: ":") else { return false }
        let scheme = address[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return false }
        let rest = address[address.index(after: colon)...]
        return !scheme.contains(".") || rest.hasPrefix("//") || !(rest.first?.isNumber ?? false)
    }

    private static func isEmailAddress(_ address: String) -> Bool {
        address.range(of: #"^[^\s@/:<>()]+@[^\s@/:<>()]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
    }

    /// Stand-ins for an address's escaped `:`, `.` or `@` while Markdown is read and written (see
    /// `escapeOffset`): Unicode noncharacters, which text never holds.
    static let colonStandIn = Character(Unicode.Scalar(UInt32(0xFDD0))!)
    static let dotStandIn = Character(Unicode.Scalar(UInt32(0xFDD1))!)
    static let atStandIn = Character(Unicode.Scalar(UInt32(0xFDD2))!)

    /// Where a backslash keeps the written-out address at `address` in `units` from being a link,
    /// as Markdown has it, GitHub's too: before the `:` after its scheme, the `.` after `www`, or
    /// an email address's `@`. A UTF-16 offset.
    static func escapeOffset(ofAddressAt address: Range<Int>, in units: [UInt16]) -> Int {
        let start = address.lowerBound
        guard prefixLength(in: units, at: start) != nil else {
            // An email address.
            return units[address].firstIndex(of: at) ?? start
        }
        if lowercased(units[start]) == UInt16(UInt8(ascii: "w")) { return start + 3 }
        return units[start + 4] == UInt16(UInt8(ascii: ":")) ? start + 4 : start + 5
    }

    /// Whether `text`, spaces aside, is one address and nothing else, as one pasted onto text to
    /// link it is.
    public static func isAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return addresses(in: trimmed) == [0..<trimmed.utf16.count]
    }

    private static let prefixes: [[UInt16]] = ["https://", "http://", "www."].map { Array($0.utf16) }

    private static func prefixLength(in units: [UInt16], at index: Int) -> Int? {
        for prefix in prefixes where index + prefix.count <= units.count {
            if zip(prefix, units[index..<(index + prefix.count)]).allSatisfy({ $0 == lowercased($1) }) {
                return prefix.count
            }
        }
        return nil
    }

    private static func lowercased(_ unit: UInt16) -> UInt16 {
        (65...90).contains(unit) ? unit + 32 : unit
    }

    private static func isASCIILetterOrDigit(_ unit: UInt16) -> Bool {
        (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit)
    }

    /// ASCII that isn't a space, a control character, or `<`, `>`, `"` or a backtick, which
    /// can't be in an address as written out.
    private static func isAddressUnit(_ unit: UInt16) -> Bool {
        unit > 32 && unit < 127 && unit != 60 && unit != 62 && unit != 34 && unit != 96
    }

    /// What ends a site's name: its path, its query or its fragment.
    private static let pathStarts: Set<UInt16> = Set("/?#".utf16)

    /// The length, in UTF-16, of a letter, digit or mark in another script at `index`: a word's.
    private static func wordLength(in units: [UInt16], at index: Int) -> Int? {
        guard units[index] >= 128 else { return nil }
        let scalarUnits = UTF16.isLeadSurrogate(units[index]) && index + 1 < units.count ? 2 : 1
        var decoder = UTF16()
        var iterator = units[index..<(index + scalarUnits)].makeIterator()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator) else { return nil }
        let properties = scalar.properties
        guard properties.isAlphabetic || properties.numericType != nil
                || [.nonspacingMark, .spacingMark, .enclosingMark].contains(properties.generalCategory) else { return nil }
        return scalarUnits
    }

    private static let trailingPunctuation: Set<UInt16> = Set("?!.,:;*_~'".utf16)
    private static let slash = UInt16(UInt8(ascii: "/")), equals = UInt16(UInt8(ascii: "="))

    private static func trimmedEnd(_ units: [UInt16], from start: Int, to end: Int) -> Int {
        var end = end
        while end > start {
            let last = units[end - 1]
            if trailingPunctuation.contains(last) {
                end -= 1
            } else if last == 41, closingBracketIsUnpaired(units, from: start, to: end, opening: 40, closing: 41) {
                end -= 1
            } else if last == 93, closingBracketIsUnpaired(units, from: start, to: end, opening: 91, closing: 93) {
                end -= 1
            } else if last >= 128 {
                // Words in another script at the end, written on right after it, aren't the
                // address's, unless they're a part of the path or a value on their own.
                var wordStart = end
                while wordStart > start, units[wordStart - 1] >= 128 { wordStart -= 1 }
                guard wordStart > start, units[wordStart - 1] != slash, units[wordStart - 1] != equals else { break }
                end = wordStart
            } else {
                break
            }
        }
        return end
    }

    /// More closing brackets than opening ones in the address so far, `)` than `(` or `]` than
    /// `[`: the last one closes a bracket around it, as in `(see https://a.b)` or `[https://a.b]`.
    private static func closingBracketIsUnpaired(_ units: [UInt16], from start: Int, to end: Int,
                                                 opening: UInt16, closing: UInt16) -> Bool {
        var depth = 0
        for unit in units[start..<end] {
            if unit == opening { depth += 1 }
            if unit == closing { depth -= 1 }
        }
        return depth < 0
    }
}
