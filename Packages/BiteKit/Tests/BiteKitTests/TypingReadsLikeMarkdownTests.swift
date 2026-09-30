import Testing
@testable import BiteKit

/// The typing shortcuts read a line as `InlineParser` reads Markdown, so typing a line gives
/// what pasting it does. From a review on 2026-10-01.
struct TypingReadsLikeMarkdownTests {
    /// The match for typing the last character of `line`.
    private func match(_ line: String, following: Character? = nil) -> InputRules.InlineMatch? {
        InputRules.inlineShortcut(prefix: String(line.dropLast()), typed: String(line.last!), following: following)
    }

    @Test func backslashesEscapeMarkers() {
        for line in ["\\*literal*", "\\**literal**", "\\~~literal~~", "\\_literal_", "*literal\\*", "**literal\\**", "\\`literal`"] {
            #expect(match(line) == nil, "\(line)")
        }
        // An escaped backslash escapes nothing.
        #expect(match("\\\\*x*")?.style == .italic)
        // In code a backslash is just a backslash, so it can't keep the code from closing.
        #expect(match("`a\\`")?.style == .code)
    }

    @Test func openCodeHoldsNoEmphasis() {
        for line in ["`**x**", "`*x*", "`~~x~~", "`_x_", "``a **b**", "x `y _z_"] {
            #expect(match(line) == nil, "\(line)")
        }
        #expect(match("`a` **b**")?.style == .bold)
        #expect(match("``a`` *b*")?.style == .italic)
        // An escaped backtick opens nothing.
        #expect(match("\\`a *b*")?.style == .italic)
    }

    @Test func codeClosesTheRunThatOpenedIt() {
        #expect(match("`a``b`")?.content == 1..<5)
        #expect(match("``a`") == nil)
        #expect(match("`a` b `c`")?.range == 6..<9)
    }

    @Test func wholeCharactersDecideWhatsAWord() {
        // Letters beyond the Basic Multilingual Plane, a letter with a combining accent, and
        // Han characters, which are letters too.
        for line in ["\u{1D49C}_x_", "\u{20BB7}_x_", "e\u{0301}_x_", "a_x_", "\u{4E2D}_x_"] {
            #expect(match(line) == nil, "\(line.debugDescription)")
        }
        // An emoji isn't a letter.
        #expect(match("\u{1F642}_x_")?.style == .italic)
        // A closing underscore needs the word to end there, as the parser has it.
        #expect(match("_x_", following: "y") == nil)
        #expect(match("_x_", following: "\u{20BB7}") == nil)
        #expect(match("_x_", following: ".")?.style == .italic)
        // Stars close inside words.
        #expect(match("*x*", following: "y")?.style == .italic)
    }

    @Test func everyUnicodeSpaceIsASpace() {
        for space in ["\u{2003}", "\u{2009}", "\u{200A}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{00A0}", "\u{1680}"] {
            #expect(match("*\(space)x*") == nil, "\(space.debugDescription)")
            #expect(match("*x\(space)*") == nil, "\(space.debugDescription)")
            #expect(match("~~\(space)x~~") == nil, "\(space.debugDescription)")
            #expect(match("`\(space)`") == nil, "\(space.debugDescription)")
        }
        // A zero-width space isn't one.
        #expect(match("*\u{200B}x*")?.style == .italic)
    }

    @Test func aTaskMarkerTakesATab() {
        #expect(MarkdownParser.parse("- [x]\titem").blocks == [Block(.todo, "item", checked: true)])
        #expect(MarkdownParser.parse("- [ ]\titem").blocks == [Block(.todo, "item")])
        #expect(MarkdownSerializer.markdown(from: BiteDocument(blocks: [Block(.bullet, "[x]\titem")])) == "- \\[x]\titem\n")
    }

    /// Markdown reads nine digits at most. A list running past 999999999 has to read back.
    @Test(arguments: [999_999_998, 999_999_999])
    func aListPastNineDigits(start: Int) {
        let document = BiteDocument(blocks: [Block(.ordered, "a", number: start), Block(.ordered, "b"), Block(.ordered, "c"),
                                             Block(.ordered, "d", indent: 1), Block(.ordered, "e")])
        let markdown = MarkdownSerializer.markdown(from: document)
        let back = MarkdownParser.parse(markdown)
        #expect(back.blocks.map(\.kind) == Array(repeating: .ordered, count: 5), "\(markdown)")
        #expect(back.blocks.map(\.text) == ["a", "b", "c", "d", "e"])
        let ordinals = ListNumbering.ordinals(for: back.blocks.map { ($0.kind, $0.indent, $0.number) })
        #expect(ordinals == [start, start + 1, start + 2, 1, start + 3])
        #expect(MarkdownSerializer.markdown(from: back) == markdown)
    }

    /// Found by the longer fuzz run of 2026-10-01: a tilde at the edge of a run was escaped
    /// though nothing that could pair with it was beside it, so a second save dropped the
    /// backslash; and a language starting with a tilde merged into a tilde fence.
    @Test func savingTwiceWritesTheSame() {
        let spaced = BiteDocument(blocks: [Block(kind: .paragraph, runs: [InlineRun("a"), InlineRun(" ", style: .bold), InlineRun("~b")])])
        let once = MarkdownSerializer.markdown(from: spaced)
        #expect(once == "a ~b\n")
        #expect(MarkdownSerializer.markdown(from: MarkdownParser.parse(once)) == once)
        let tildes = BiteDocument(blocks: [Block(kind: .paragraph, runs: [InlineRun("a~", style: .italic), InlineRun("~b")])])
        let written = MarkdownSerializer.markdown(from: tildes)
        #expect(MarkdownParser.parse(written).blocks[0].runs == tildes.blocks[0].runs)
        let code = BiteDocument(blocks: [Block(.code, "x", language: "~``!")])
        let fenced = MarkdownSerializer.markdown(from: code)
        #expect(fenced == "~~~ ~``!\nx\n~~~\n")
        #expect(MarkdownParser.parse(fenced) == code)
    }

    /// Checking every pair for every token made a long line quadratic: a line of 400,000
    /// characters took five seconds. Four times the line should take about four times as long.
    @Test(arguments: ["**x** ", "a* ", "~~a~~ ", "_a_ "])
    func longLinesParseInLinearTime(unit: String) {
        func seconds(_ count: Int) -> Double {
            let line = String(repeating: unit, count: count)
            let clock = ContinuousClock()
            var best = Double.infinity
            for _ in 0..<3 {
                let start = clock.now
                _ = InlineParser.parse(line)
                let elapsed = start.duration(to: clock.now)
                best = min(best, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
            return best
        }
        let short = seconds(4000)
        let long = seconds(16000)
        #expect(long < short * 10, "\(unit.debugDescription): \(short) s, then \(long) s")
    }
}
