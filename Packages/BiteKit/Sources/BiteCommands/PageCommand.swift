import Foundation
import BiteKit

/// What Bite's command line tool, or an AI through its MCP server, asks of Bite's pages: all a
/// person does on them, but switching dots, which `open` does.
public enum PageCommand: Equatable, Sendable {
    case list
    case read(PageReference)
    /// Lines saying the text, on one page or on them all.
    case search(String, page: PageReference?)
    /// The to-dos left, or, `done`, every to-do, on one page or on them all.
    case toDos(page: PageReference?, done: Bool)
    case statistics(PageReference)
    /// Lines at the end of the page, as if typed there: an empty last line takes the first. Each a
    /// to-do, `asToDo`.
    case add(PageReference, text: String, asToDo: Bool, ifVersion: String?)
    case insert(PageReference, text: String, at: LinePosition, ifVersion: String?)
    case replace(PageReference, lines: LineRange, text: String, ifVersion: String?)
    case delete(PageReference, lines: LineRange, ifVersion: String?)
    /// Lines moved on their page, or, `to` another, onto that one.
    case move(PageReference, lines: LineRange, to: PageReference?, at: LinePosition, ifVersion: String?)
    case findAndReplace(PageReference, find: String, replacement: String, all: Bool, ifVersion: String?)
    case setToDo(PageReference, ToDoTarget, done: Bool, ifVersion: String?)
    case write(PageReference, text: String, ifVersion: String?)
    case clear(PageReference, ifVersion: String?)
    case open(PageReference)
}

/// A to-do, by its line or by what it says.
public enum ToDoTarget: Equatable, Sendable {
    case line(Int)
    case text(String)
}

/// What a command found or did.
public struct CommandResult: Equatable, Sendable {
    /// For a person, or an AI, to read.
    public var text: String
    /// The same for a program: what `--json` gives.
    public var json: JSONValue
    /// A page read, as its Markdown, which the command line prints as it is unless asked to number
    /// its lines.
    public var markdown: String?

    public init(text: String, json: JSONValue, markdown: String? = nil) {
        self.text = text
        self.json = json
        self.markdown = markdown
    }
}

extension PageCommand {
    /// Whether the command changes a page.
    public var changes: Bool {
        switch self {
        case .list, .read, .search, .toDos, .statistics, .open: false
        default: true
        }
    }

    public func run(on access: some PageAccess, now: Date = .now) async throws -> CommandResult {
        switch self {
        case .list:
            return try await list(access, now: now)
        case .read(let reference):
            let (page, markdown) = try await read(reference, in: access)
            return Self.read(page: page, markdown: markdown)
        case .search(let query, let reference):
            return try await search(query, on: reference, in: access)
        case .toDos(let reference, let done):
            return try await toDos(on: reference, done: done, in: access)
        case .statistics(let reference):
            let (page, markdown) = try await read(reference, in: access)
            let modified = await access.modified()
            let statistics = PageStatistics(document: MarkdownParser.parse(markdown))
            let changed = modified.indices.contains(page) ? modified[page] : nil
            let text = "The \(page.pageName) page has \(Self.counted(statistics.words, "word")), \(Self.counted(statistics.characters, "character")) and \(Self.counted(statistics.paragraphs, "paragraph"))"
                + (changed.map { ", and changed \(Self.relative($0, now: now))." } ?? ".")
            var json = Self.about(page)
            json["words"] = .int(statistics.words)
            json["characters"] = .int(statistics.characters)
            json["paragraphs"] = .int(statistics.paragraphs)
            json["modified"] = changed.map { .string($0.ISO8601Format()) } ?? .null
            return CommandResult(text: text, json: .object(json))
        case .add(let reference, let text, let asToDo, let ifVersion):
            let new = PageLines.given(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { asToDo ? Self.toDo($0) : $0 }
            guard !new.isEmpty else { throw CommandError("Give the text to add.") }
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, _ in
                if lines.lines.last?.isEmpty == true { lines.lines.removeLast() }
                lines.insert(new, at: lines.count)
                return "Added \(Self.counted(new.count, asToDo ? "to-do" : "line")) at the end"
            }
        case .insert(let reference, let text, let position, let ifVersion):
            let new = PageLines.given(text)
            guard !text.isEmpty else { throw CommandError("Give the text to put in.") }
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                lines.insert(new, at: try position.position(on: lines.count, page: name))
                return "Put \(Self.counted(new.count, "line")) in \(position)"
            }
        case .replace(let reference, let range, let text, let ifVersion):
            guard !text.isEmpty else { throw CommandError("Give the new text, or delete the lines instead.") }
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                try lines.check(range, page: name)
                let new = PageLines.given(text)
                lines.replace(range, with: new)
                return "Replaced \(range) with \(Self.counted(new.count, "line"))"
            }
        case .delete(let reference, let range, let ifVersion):
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                try lines.check(range, page: name)
                lines.remove(range)
                return "Deleted \(range)"
            }
        case .move(let reference, let range, let destination, let position, let ifVersion):
            return try await move(reference, range, to: destination, at: position, ifVersion: ifVersion, in: access)
        case .findAndReplace(let reference, let find, let replacement, let all, let ifVersion):
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                let found = try lines.replaceText(find, with: replacement, all: all, page: name)
                return "Replaced \"\(find)\"" + (found == 1 ? "" : " \(found) times")
            }
        case .setToDo(let reference, let target, let done, let ifVersion):
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                let number: Int
                switch target {
                case .line(let line): number = line
                case .text(let text): number = try lines.toDo(saying: text, page: name)
                }
                let what = lines.toDo(at: number)?.text ?? ""
                try lines.setToDo(at: number, done: done, page: name)
                return "Ticked \"\(what)\" \(done ? "off" : "on again"), on line \(number)"
            }
        case .write(let reference, let text, let ifVersion):
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, _ in
                lines = PageLines(lines: text.isEmpty ? [] : PageLines.given(text))
                return "Wrote the page, \(Self.counted(lines.count, "line"))"
            }
        case .clear(let reference, let ifVersion):
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, _ in
                lines = PageLines(lines: [])
                return "Cleared the page"
            }
        case .open(let reference):
            let page = try await reference.page(in: access)
            try await access.open(page: page)
            return CommandResult(text: "Bite shows the \(page.pageName) page.", json: .object(Self.about(page)))
        }
    }

    // MARK: Reading

    private func read(_ reference: PageReference, in access: some PageAccess) async throws -> (Int, String) {
        let page = try await reference.page(in: access)
        let pages = try await access.pages()
        guard pages.indices.contains(page) else { throw CommandError("Bite has no \(page.pageName) page yet.") }
        return (page, pages[page])
    }

    static func read(page: Int, markdown: String) -> CommandResult {
        let lines = PageLines(markdown)
        let version = PageLines.version(of: markdown)
        let text = lines.count == 0
            ? "The \(page.pageName) page (\(page + 1)) is empty, version \(version)."
            : "The \(page.pageName) page (\(page + 1)), version \(version), \(counted(lines.count, "line")):\n" + lines.numbered()
        var json = about(page)
        json["version"] = .string(version)
        json["title"] = PageGlance(markdown: markdown).title.map { .string($0) } ?? .null
        json["markdown"] = .string(markdown)
        json["lines"] = .array(lines.lines.enumerated().map { JSONValue.object(["line": .int($0.offset + 1), "text": .string($0.element)]) })
        return CommandResult(text: text, json: .object(json), markdown: markdown)
    }

    private func list(_ access: some PageAccess, now: Date) async throws -> CommandResult {
        let pages = try await access.pages()
        let modified = await access.modified()
        let shown = await access.shownPage()
        var rows: [String] = []
        var json: [JSONValue] = []
        for (page, markdown) in pages.enumerated() {
            let lines = PageLines(markdown)
            let title = PageGlance(markdown: markdown).title
            let changed = modified.indices.contains(page) ? modified[page] : nil
            let toDos = lines.toDos
            let done = toDos.filter(\.done).count
            var row = "\(page + 1) \(page.pageName)" + (page == shown ? " (shown)" : "") + ": "
            if lines.count == 0 {
                row += "empty"
            } else {
                row += title.map { "\"\($0)\", " } ?? ""
                row += Self.counted(lines.count, "line")
                row += toDos.isEmpty ? "" : ", \(Self.counted(toDos.count - done, "to-do")) left of \(toDos.count)"
                row += changed.map { ", changed \(Self.relative($0, now: now))" } ?? ""
            }
            rows.append(row)
            var about = Self.about(page)
            about["title"] = title.map { .string($0) } ?? .null
            about["lines"] = .int(lines.count)
            about["empty"] = .bool(lines.count == 0)
            about["shown"] = .bool(page == shown)
            about["todos"] = ["left": .int(toDos.count - done), "done": .int(done)]
            about["version"] = .string(PageLines.version(of: markdown))
            about["modified"] = changed.map { .string($0.ISO8601Format()) } ?? .null
            json.append(.object(about))
        }
        return CommandResult(text: "Bite's pages:\n" + rows.joined(separator: "\n"), json: .array(json))
    }

    private func search(_ query: String, on reference: PageReference?, in access: some PageAccess) async throws -> CommandResult {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError("Give the text to look for.") }
        let pages = try await access.pages()
        let only = try await reference?.page(in: access)
        var found: [(page: Int, line: Int, text: String)] = []
        for (page, markdown) in pages.enumerated() where only == nil || only == page {
            let lines = PageLines(markdown)
            found += lines.lines(saying: query).map { (page: page, line: $0, text: lines.lines[$0 - 1]) }
        }
        let place = only.map { "the \($0.pageName) page" } ?? "Bite's pages"
        let text = found.isEmpty
            ? "Nothing on \(place) says \"\(query)\"."
            : "\(Self.counted(found.count, "line")) on \(place) say\(found.count == 1 ? "s" : "") \"\(query)\":\n"
                + found.map { "\($0.page.pageName) \($0.line): \($0.text)" }.joined(separator: "\n")
        let json = JSONValue.array(found.map {
            JSONValue.object(["page": .int($0.page + 1), "color": .string($0.page.pageName), "line": .int($0.line), "text": .string($0.text)])
        })
        return CommandResult(text: text, json: json)
    }

    private func toDos(on reference: PageReference?, done: Bool, in access: some PageAccess) async throws -> CommandResult {
        let pages = try await access.pages()
        let only = try await reference?.page(in: access)
        var found: [(page: Int, line: Int, done: Bool, text: String)] = []
        for (page, markdown) in pages.enumerated() where only == nil || only == page {
            found += PageLines(markdown).toDos.filter { done || !$0.done }.map { (page: page, line: $0.line, done: $0.done, text: $0.text) }
        }
        let place = only.map { "the \($0.pageName) page" } ?? "Bite's pages"
        let text = found.isEmpty
            ? "No \(done ? "to-dos" : "to-dos left") on \(place)."
            : "\(Self.counted(found.count, "to-do"))\(done ? "" : " left") on \(place):\n"
                + found.map { "\($0.page.pageName) \($0.line): " + (done ? ($0.done ? "[x] " : "[ ] ") : "") + $0.text }.joined(separator: "\n")
        let json = JSONValue.array(found.map {
            JSONValue.object(["page": .int($0.page + 1), "color": .string($0.page.pageName), "line": .int($0.line), "done": .bool($0.done), "text": .string($0.text)])
        })
        return CommandResult(text: text, json: json)
    }

    // MARK: Changing

    /// Changes a page as read, and has Bite take the change in. `change` is given the page's lines and
    /// its name, and says what it did.
    private func edit(_ reference: PageReference, ifVersion: String?, in access: some PageAccess,
                      _ change: (inout PageLines, String) throws -> String) async throws -> CommandResult {
        let (page, before) = try await read(reference, in: access)
        try Self.check(ifVersion, of: before, page: page)
        var lines = PageLines(before)
        let done = try change(&lines, page.pageName)
        return try await Self.commit(page: page, before: before, after: lines.markdown, done: done, in: access)
    }

    private static func check(_ version: String?, of markdown: String, page: Int) throws {
        guard let version, !version.isEmpty else { return }
        let current = PageLines.version(of: markdown)
        guard version.lowercased() != current else { return }
        throw CommandError("The \(page.pageName) page has changed since version \(version): it's now version \(current). Read it again, and change it as it is now.")
    }

    private static func commit(page: Int, before: String, after: String, done: String, in access: some PageAccess) async throws -> CommandResult {
        var json = about(page)
        guard after != before else {
            json["version"] = .string(PageLines.version(of: before))
            json["changed"] = false
            return CommandResult(text: "Nothing to change: the \(page.pageName) page is that way already.", json: .object(json))
        }
        json["changed"] = true
        guard let now = try await access.change(page: page, from: before, to: after) else {
            json["taken"] = false
            return CommandResult(text: "\(done). Bite isn't running, so the change waits on the \(page.pageName) page, to go in as Bite next runs.", json: .object(json))
        }
        let lines = PageLines(now)
        let version = PageLines.version(of: now)
        json["taken"] = true
        json["version"] = .string(version)
        json["lines"] = .int(lines.count)
        let state = lines.count == 0 ? "is now empty" : "now has \(counted(lines.count, "line"))"
        return CommandResult(text: "\(done). The \(page.pageName) page \(state), version \(version).", json: .object(json))
    }

    /// Lines moved on their page, or onto another: put on the other page first, then taken off this
    /// one, so a move cut short leaves them on both rather than on neither.
    private func move(_ reference: PageReference, _ range: LineRange, to destination: PageReference?, at position: LinePosition,
                      ifVersion: String?, in access: some PageAccess) async throws -> CommandResult {
        let (page, before) = try await read(reference, in: access)
        let target = try await destination?.page(in: access) ?? page
        guard target != page else {
            return try await edit(reference, ifVersion: ifVersion, in: access) { lines, name in
                try lines.check(range, page: name)
                try lines.move(range, to: try position.position(on: lines.count, page: name), page: name)
                return "Moved \(range) \(position)"
            }
        }
        try Self.check(ifVersion, of: before, page: page)
        var lines = PageLines(before)
        try lines.check(range, page: page.pageName)
        let moved = lines.remove(range)
        let pages = try await access.pages()
        var targetLines = PageLines(pages[target])
        targetLines.insert(moved, at: try position.position(on: targetLines.count, page: target.pageName))
        let put = try await Self.commit(page: target, before: pages[target], after: targetLines.markdown,
                                        done: "Put \(Self.counted(moved.count, "line")) \(position)", in: access)
        let taken = try await Self.commit(page: page, before: before, after: lines.markdown,
                                          done: "Moved \(range) to the \(target.pageName) page", in: access)
        return CommandResult(text: taken.text + "\n" + put.text, json: ["from": taken.json, "to": put.json])
    }

    // MARK: Words

    /// A line as a to-do: kept as it is if one already, its list marker, if any, made a box.
    static func toDo(_ line: String) -> String {
        guard PageLines(lines: [line]).toDo(at: 1) == nil else { return line }
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        var text = line.dropFirst(indent.count)
        for marker in ["- ", "* ", "+ "] where text.hasPrefix(marker) {
            text = text.dropFirst(marker.count)
            break
        }
        return String(indent) + "- [ ] " + String(text)
    }

    static func about(_ page: Int) -> [String: JSONValue] {
        ["page": .int(page + 1), "color": .string(page.pageName)]
    }

    static func counted(_ count: Int, _ thing: String) -> String {
        "\(count) \(thing)\(count == 1 ? "" : "s")"
    }

    static func relative(_ date: Date, now: Date) -> String {
        guard abs(date.timeIntervalSince(now)) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
