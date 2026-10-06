import Foundation

/// A to-do ticked off, or ticked on again, from a widget.
public struct PageTick: Codable, Sendable, Hashable {
    /// The page, counting from 0 along the dot bar.
    public var page: Int
    /// Where the to-do was on the page (see `PageGlance.Line.block`).
    public var block: Int
    /// The to-do's text, to find it by if the page has changed since.
    public var text: String
    public var done: Bool

    public init(page: Int, block: Int, text: String, done: Bool) {
        self.page = page
        self.block = block
        self.text = text
        self.done = done
    }
}

public enum PageToDos {
    /// The page with a to-do ticked off or on: the one at `block`, or, where the page has changed
    /// since, the to-do with the same text nearest it. Nil when the page has no such to-do any more.
    public static func markdown(_ markdown: String, ticking tick: PageTick) -> String? {
        var document = MarkdownParser.parse(markdown)
        let blocks = document.blocks
        let matches = blocks.indices.filter { blocks[$0].kind == .todo && blocks[$0].text == tick.text }
        guard let index = matches.min(by: { abs($0 - tick.block) < abs($1 - tick.block) }) else { return nil }
        guard blocks[index].isChecked != tick.done else { return markdown }
        document.blocks[index].isChecked = tick.done
        return MarkdownSerializer.markdown(from: document)
    }
}

extension PageShelf {
    /// The folder Bite shares with its widgets.
    public static let appGroup = "group.com.chenyeni.bite"

    private var ticksFile: URL {
        folder.appending(path: "Ticks.json")
    }

    /// Leaves a widget's tick for Bite, which takes it in as it next runs (see `takeTicks`).
    public func leave(_ tick: PageTick) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ticks = readTicks() + [tick]
        try JSONEncoder().encode(ticks).write(to: ticksFile, options: .atomic)
    }

    /// The ticks left since Bite last took them, oldest first, which are then gone from the shelf.
    public func takeTicks() -> [PageTick] {
        let ticks = readTicks()
        if !ticks.isEmpty { try? FileManager.default.removeItem(at: ticksFile) }
        return ticks
    }

    private func readTicks() -> [PageTick] {
        guard let data = try? Data(contentsOf: ticksFile) else { return [] }
        return (try? JSONDecoder().decode([PageTick].self, from: data)) ?? []
    }

    /// A tick and when it was made, for a widget that shows a to-do ticked off for a moment before
    /// it goes: gone at once, the box tapped in its place was another to-do's, which the system
    /// left showing as if still being tapped.
    public struct ShownTick: Codable, Sendable, Hashable {
        public var tick: PageTick
        public var date: Date
    }

    private var shownFile: URL {
        folder.appending(path: "Shown.json")
    }

    /// Notes a tick made in a widget, keeping those of the last minute.
    public func noteShown(_ tick: PageTick, at date: Date = .now) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kept = shownTicks(since: date.addingTimeInterval(-60)) + [ShownTick(tick: tick, date: date)]
        try JSONEncoder().encode(kept).write(to: shownFile, options: .atomic)
    }

    /// The ticks made in widgets since `date`, oldest first.
    public func shownTicks(since date: Date) -> [ShownTick] {
        guard let data = try? Data(contentsOf: shownFile),
              let ticks = try? JSONDecoder().decode([ShownTick].self, from: data) else { return [] }
        return ticks.filter { $0.date >= date }
    }
}
