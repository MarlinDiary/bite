import Foundation

/// Text added to the end of a page from outside the editor, as from Siri or Shortcuts, or shared to
/// Bite: as if it were typed there, the caret at the end of the page. An empty last line, a
/// paragraph or a list item, takes it as it is; after a line with something on it, it goes on a new
/// line, carrying on a list the page ends with, as Return does.
public enum PageAddition {
    /// `markdown` with `text` added, as a to-do whatever the page ends with if `asToDo`. Each line
    /// of the text is a line of the page, as written: Markdown in it is kept as text, as typing it
    /// would only through the format bar. The same Markdown when there's nothing to add.
    public static func markdown(_ markdown: String, adding text: String, asToDo: Bool) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { [InlineRun($0)] }
        return self.markdown(markdown, adding: lines, asToDo: asToDo)
    }

    /// `markdown` with `lines` added, each a line of text in its styles and links, as a web page
    /// shared to Bite is a line linking there. Lines with nothing on them are left out.
    public static func markdown(_ markdown: String, adding lines: [[InlineRun]], asToDo: Bool) -> String {
        let lines = lines.filter { !$0.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return markdown }
        var blocks = MarkdownParser.parse(markdown).blocks
        for line in lines {
            add(line, asToDo: asToDo, to: &blocks)
        }
        return MarkdownSerializer.markdown(from: BiteDocument(blocks: blocks))
    }

    /// The lines added at the end of `before` to make `after`, as they are in `after`, in their
    /// styles and links but not their kind, which is the page's they went on: what's then to go on
    /// another page instead. Nil when `after` isn't `before` with lines added at its end, as when a
    /// line above them has changed.
    public static func linesAdded(to before: String, making after: String) -> [[InlineRun]]? {
        let before = MarkdownParser.parse(before).blocks
        let after = MarkdownParser.parse(after).blocks
        let kept = keptLineCount(of: before)
        guard after.count >= kept, Array(after.prefix(kept)) == Array(before.prefix(kept)) else { return nil }
        // The empty last line, still empty and with nothing after it, was left as it was.
        if after.count == before.count, after.last == before.last { return [] }
        return after.dropFirst(kept).map(\.runs).filter { !$0.map(\.text).joined().isEmpty }
    }

    /// A page that had `lines` added at its end to its own lines, `own`, as `markdown(_:adding:)`
    /// adds them, changed since to `now`: what's now the page's own lines, and what's now added. A
    /// change to the page's own lines stays the page's, as ticking a to-do; one to the lines added
    /// goes with them. Changes to both, the lines added still as many and of the same kinds, are
    /// each kept with theirs. A change that runs from one into the other, as joining the first
    /// line added to the line above it, takes the lines added in as the page's own, and then
    /// nothing's added.
    public static func split(_ now: String, own: String, lines: [[InlineRun]]) -> (own: String, lines: [[InlineRun]]) {
        let lines = lines.filter { !$0.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty }
        let ownBlocks = MarkdownParser.parse(own).blocks
        let was = MarkdownParser.parse(markdown(own, adding: lines, asToDo: false)).blocks
        let now = MarkdownParser.parse(now).blocks
        guard was != now else { return (own, lines) }
        // Where the lines added start: after the page's own, but an empty last line they filled.
        let start = lines.isEmpty ? was.count : keptLineCount(of: ownBlocks)
        let filled = !lines.isEmpty && ownBlocks.count > start
        let added = was.count - start
        func pageOwn(_ blocks: some Collection<Block>) -> String {
            MarkdownSerializer.markdown(from: BiteDocument(blocks: Array(blocks) + (filled ? [ownBlocks[ownBlocks.count - 1]] : [])))
        }
        func runs(_ blocks: some Collection<Block>) -> [[InlineRun]] {
            blocks.map(\.runs).filter { !$0.map(\.text).joined().isEmpty }
        }
        var prefix = 0
        while prefix < min(was.count, now.count), was[prefix] == now[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(was.count, now.count) - prefix, was[was.count - 1 - suffix] == now[now.count - 1 - suffix] { suffix += 1 }
        if was.count - suffix <= start {
            return (pageOwn(now.dropLast(added)), lines)
        }
        if prefix >= start {
            return (MarkdownSerializer.markdown(from: BiteDocument(blocks: ownBlocks)), runs(now.dropFirst(start)))
        }
        // Changed in both at once, as a to-do ticked and a word typed, each still as many lines.
        if now.count == was.count, now[start...].map(\.kind) == was[start...].map(\.kind) {
            return (pageOwn(now[..<start]), runs(now[start...]))
        }
        return (MarkdownSerializer.markdown(from: BiteDocument(blocks: now)), [])
    }

    /// How many of `markdown`'s lines what's added goes after and leaves as they are: all of them,
    /// but an empty last line, which the first line added fills.
    public static func keptLineCount(of markdown: String) -> Int {
        keptLineCount(of: MarkdownParser.parse(markdown).blocks)
    }

    private static func keptLineCount(of blocks: [Block]) -> Int {
        blocks.last.map { takesText($0) ? blocks.count - 1 : blocks.count } ?? 0
    }

    private static func takesText(_ block: Block) -> Bool {
        block.text.isEmpty && (block.kind == .paragraph || block.kind.isList)
    }

    private static func add(_ runs: [InlineRun], asToDo: Bool, to blocks: inout [Block]) {
        guard let last = blocks.last else {
            blocks.append(Block(kind: asToDo ? .todo : .paragraph, runs: runs))
            return
        }
        if takesText(last) {
            blocks[blocks.count - 1] = line(runs, like: last, asToDo: asToDo, keepsNumber: true)
        } else if last.kind.isList {
            blocks.append(line(runs, like: last, asToDo: asToDo, keepsNumber: false))
        } else {
            blocks.append(Block(kind: asToDo ? .todo : .paragraph, runs: runs))
        }
    }

    /// A line of `other`'s kind at its level, or a to-do there: unticked, and in a numbered list,
    /// numbered on from it, or as it was when it's `other` filled in.
    private static func line(_ runs: [InlineRun], like other: Block, asToDo: Bool, keepsNumber: Bool) -> Block {
        let kind: BlockKind = asToDo ? .todo : other.kind
        let ordered = kind == .ordered
        return Block(kind: kind, indent: other.indent, number: ordered && keepsNumber ? other.number : nil,
                     numberStyle: ordered ? other.numberStyle : nil, runs: runs)
    }
}
