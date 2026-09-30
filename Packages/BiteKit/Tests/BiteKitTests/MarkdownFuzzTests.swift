import Testing
@testable import BiteKit

/// Random documents through Markdown and back, their text built from pieces Markdown cares
/// about. Deterministic: the same seed makes the same documents every run.
struct MarkdownFuzzTests {
    private struct Random {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }

        mutating func chance(_ oneIn: Int) -> Bool {
            int(1...oneIn) == 1
        }

        mutating func pick<T>(_ items: [T]) -> T {
            items[int(0...(items.count - 1))]
        }
    }

    private static let pieces = [
        "a", "b", "word", "\u{4E2D}\u{6587}", "🙂", " ", " ", "  ", "\t",
        "*", "**", "***", "_", "__", "x_y", "~", "~~", "`", "``", "```", "~~~", "\\", "\\*",
        "#", "## ", "- ", "-", "--", "---", "+ ", "* ", "> ", "1. ", "3) ", "12.", "[ ] ", "[x]", "[X] ",
        "a. ", "i. ", "B) ", "iv. ", "Q. ", "OK. ", "mix. ", "x.",
        "|", "!", "(", ")", "[", "]", "<", "=", ":", ".",
    ]

    private static func text(_ random: inout Random, pieces count: ClosedRange<Int>) -> String {
        (0..<random.int(count)).map { _ in random.pick(pieces) }.joined()
    }

    private static func document(_ random: inout Random) -> BiteDocument {
        let blocks = (0..<random.int(1...8)).map { _ -> Block in
            let kind = random.pick(BlockKind.allCases)
            var runs: [InlineRun] = []
            if kind == .code {
                runs = [InlineRun(text(&random, pieces: 0...4))]
            } else {
                for _ in 0..<random.int(0...3) {
                    var style: InlineStyle = []
                    for option in [InlineStyle.bold, .italic, .strikethrough, .code] where random.chance(4) {
                        style.insert(option)
                    }
                    runs.append(InlineRun(text(&random, pieces: 1...3), style: style))
                }
            }
            return Block(kind: kind, indent: random.int(0...3), isChecked: random.chance(2),
                         number: random.chance(3) ? random.pick([0, 2, 7, 9, 10, 26, 27, 99, 4000, 123_456]) : nil,
                         numberStyle: random.chance(2) ? random.pick(NumberStyle.allCases) : nil,
                         language: random.pick(["", "", "swift", "c++", "a b", "x`y"]), runs: runs)
        }
        return BiteDocument(blocks: blocks)
    }

    /// The document as Markdown says it: nesting it can't show is pulled up, a written number
    /// and style count only where a list starts (and 1 goes without saying), a style goes where
    /// Markdown would write the first number in digits, code lines in a row share one fence and
    /// its language, and whitespace isn't styled.
    private static func canonical(_ document: BiteDocument, keepingStyles: Bool) -> BiteDocument {
        var blocks = document.blocks
        let levels = ListNesting.levels(for: blocks.map { ($0.kind, $0.indent) })
        for index in blocks.indices {
            blocks[index].indent = levels[index]
        }
        let styles = MarkdownSerializer.writableStyles(blocks, levels: levels)
        for index in blocks.indices { blocks[index].numberStyle = styles[index] }
        let starts = ListNumbering.startsList(blocks.map { ($0.kind, $0.indent, $0.numberStyle) })
        var index = 0
        while index < blocks.count {
            if blocks[index].kind == .code {
                var end = index
                while end < blocks.count, blocks[end].kind == .code { end += 1 }
                let language = blocks[index..<end].first(where: { !$0.language.isEmpty })?.language ?? ""
                for line in index..<end { blocks[line].language = language }
                index = end
                continue
            }
            if blocks[index].kind == .ordered, !starts[index] {
                blocks[index].number = nil
                blocks[index].numberStyle = nil
            }
            if blocks[index].kind == .ordered, blocks[index].number == 1 {
                blocks[index].number = nil
            }
            var words = MarkdownSerializer.words(blocks[index].runs)
            if !keepingStyles { words = [InlineRun(words.map(\.text).joined())] }
            blocks[index].runs = InlineRun.normalized(words)
            index += 1
        }
        return BiteDocument(blocks: blocks)
    }

    @Test func randomDocumentsReadBack() {
        var random = Random(state: 20_260_930)
        for _ in 0..<5000 {
            let document = Self.document(&random)
            let markdown = MarkdownSerializer.markdown(from: document)
            let back = MarkdownParser.parse(markdown)
            // Text, kinds, levels, numbers and languages always survive.
            #expect(Self.canonical(back, keepingStyles: false) == Self.canonical(document, keepingStyles: false),
                    "\(markdown.debugDescription)")
            // Styles too, unless bold or italic changes mid-word somewhere; then the serializer
            // may let a style go rather than write something ambiguous.
            if !document.blocks.contains(where: { MarkdownSerializer.emphasisChangesMidWord($0.runs) }) {
                #expect(Self.canonical(back, keepingStyles: true) == Self.canonical(document, keepingStyles: true),
                        "\(markdown.debugDescription)")
            }
            // Writing what was read gives the same Markdown again.
            #expect(MarkdownSerializer.markdown(from: back) == markdown, "\(markdown.debugDescription)")
        }
    }

    /// Whatever Markdown comes in, reading it and writing it back settles at once.
    @Test func randomMarkdownSettles() {
        var random = Random(state: 7)
        let lineStarts = ["", "", " ", "    ", "\t", "- ", "* ", "1. ", "2) ", "- [ ] ", "# ", "#### ", "> ", "```", "~~~", "---",
                          "a. ", "i. ", "C) ", "IV. ", "ok. ", "z."]
        for _ in 0..<5000 {
            let markdown = (0..<random.int(1...6)).map { _ in
                random.pick(lineStarts) + Self.text(&random, pieces: 0...4)
            }.joined(separator: random.pick(["\n", "\r\n"]))
            let once = MarkdownSerializer.markdown(from: MarkdownParser.parse(markdown))
            let twice = MarkdownSerializer.markdown(from: MarkdownParser.parse(once))
            #expect(twice == once, "\(markdown.debugDescription)")
        }
    }
}
