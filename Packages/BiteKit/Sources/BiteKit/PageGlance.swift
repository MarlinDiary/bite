import Foundation

/// A page as a widget shows it: its lines as Bite draws them, each numbered item's number worked
/// out, for a view that can't lay text out as the editor does. Empty lines at either end are left
/// out, and empty lines in a row count as one: a widget has little room.
public struct PageGlance: Sendable, Hashable {
    public struct Line: Sendable, Hashable {
        /// Where the line is on the page, counting the page's lines from 0, empty ones too: what a
        /// to-do ticked off in a widget is found by.
        public var block: Int
        public var kind: BlockKind
        public var indent: Int
        public var isChecked: Bool
        /// What a numbered item shows in front of it, as Bite shows it: `1.`, `a.`, `iv.`. Nil for
        /// every other line.
        public var label: String?
        public var runs: [InlineRun]

        public var text: String {
            runs.map(\.text).joined()
        }

        /// A line with nothing on it, which shows as a little room between the lines round it.
        public var isBlank: Bool {
            kind == .paragraph && runs.allSatisfy(\.text.isEmpty)
        }
    }

    public var lines: [Line]

    public init(markdown: String) {
        let blocks = MarkdownParser.parse(markdown).blocks
        let numbers = ListNumbering.numbers(for: blocks.map { ($0.kind, $0.indent, $0.number, $0.numberStyle) })
        var lines: [Line] = []
        for (index, (block, number)) in zip(blocks, numbers).enumerated() {
            let line = Line(block: index, kind: block.kind, indent: block.indent, isChecked: block.isChecked,
                            label: number.map { ListNumbering.label(for: $0.ordinal, indent: block.indent, style: $0.style) },
                            runs: block.runs)
            if line.isBlank, lines.last?.isBlank ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isBlank == true { lines.removeLast() }
        self.lines = lines
    }

    /// True for a page with nothing on it but empty lines.
    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// The page without its title: its first line, when that's a heading, and the empty line
    /// after it. A page with nothing else on it keeps it, rather than showing as if empty.
    public func withoutTitle() -> PageGlance {
        guard lines.first?.kind.isHeading == true else { return self }
        var glance = self
        glance.lines.removeFirst()
        if glance.lines.first?.isBlank == true { glance.lines.removeFirst() }
        return glance.isEmpty ? self : glance
    }

    /// What the page is about, for a line next to the clock: its first line with words on it.
    public var title: String? {
        lines.lazy.map { $0.text.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// The page's to-dos: how many are still to do, and how many in all.
    public var toDos: (open: Int, all: Int) {
        let toDos = lines.filter { $0.kind == .todo }
        return (toDos.count { !$0.isChecked }, toDos.count)
    }
}
