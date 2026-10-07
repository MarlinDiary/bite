import Foundation
import BiteKit

/// Bite's pages for AI apps: a Model Context Protocol server, spoken to a line of JSON-RPC at a time
/// over standard input and output (`bite mcp`). Its tools do all the command line does.
public struct MCPServer<Access: PageAccess>: Sendable {
    public let access: Access
    /// The tool's own version, as it tells the AI app.
    public let version: String

    public init(access: Access, version: String) {
        self.access = access
        self.version = version
    }

    /// The protocol's versions this server speaks, newest first.
    static var protocolVersions: [String] {
        ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    }

    /// The reply to a line from the AI app, or nil for one that needs none: a notification.
    public func reply(to line: String) async -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let message = JSONValue(parsing: line) else {
            return Self.error(id: .null, code: -32700, "That isn't JSON.").encoded()
        }
        if case .array(let batch) = message {
            var replies: [JSONValue] = []
            for message in batch {
                if let reply = await reply(to: message) { replies.append(reply) }
            }
            return replies.isEmpty ? nil : JSONValue.array(replies).encoded()
        }
        return await reply(to: message)?.encoded()
    }

    func reply(to message: JSONValue) async -> JSONValue? {
        guard let method = message["method"]?.string else {
            // A reply to a request: the server makes none.
            return nil
        }
        // A notification, as that the app is ready, has no id and gets no reply.
        guard let id = message["id"] else { return nil }
        let parameters = message["params"] ?? [:]
        switch method {
        case "initialize":
            let asked = parameters["protocolVersion"]?.string ?? ""
            return Self.result(id: id, [
                "protocolVersion": .string(Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "bite", "title": "Bite", "version": .string(version)],
                "instructions": .string(Self.instructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(Self.tools.map(\.json))])
        case "tools/call":
            guard let name = parameters["name"]?.string, let tool = Self.tools.first(where: { $0.name == name }) else {
                return Self.error(id: id, code: -32602, "There's no tool \"\(parameters["name"]?.string ?? "")\".")
            }
            let arguments = Arguments(parameters["arguments"] ?? [:])
            do {
                let command = try tool.command(arguments)
                let result = try await command.run(on: access)
                return Self.result(id: id, ["content": [["type": "text", "text": .string(result.text)]], "isError": false])
            } catch {
                let message = (error as? CommandError)?.message ?? error.localizedDescription
                return Self.result(id: id, ["content": [["type": "text", "text": .string(message)]], "isError": true])
            }
        default:
            return Self.error(id: id, code: -32601, "There's no method \"\(method)\".")
        }
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, _ message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]
    }

    static var instructions: String {
        """
        Bite is a scratchpad of seven pages, one for each dot along its dot bar: \
        \(DotPalette.colors.indices.map { "\($0 + 1) \($0.pageName)" }.joined(separator: ", ")). \
        Name a page by its colour, its number, or "current" for the page Bite shows.

        Each page is Markdown, a line of it for each line on the page: headings (#, ##, ###), \
        bullets (- ), numbered lists (1. ), to-dos (- [ ] and - [x]), quotes (> ), code between ``` \
        fences, dividers (---), **bold**, *italic*, ~~strikethrough~~, `code` and [links](https://…); \
        a list item one deeper is indented four spaces.

        Read a page before changing its lines by number, and pass the version read as if_version: a \
        page changed since is then left alone, to read again. Bite takes each change in as if typed \
        there, put together with anything typed meanwhile, and keeps it on the person's other \
        devices through iCloud.
        """
    }
}

/// A tool call's arguments, read as the tool needs them.
struct Arguments {
    let values: JSONValue

    init(_ values: JSONValue) {
        self.values = values
    }

    func string(_ key: String) -> String? {
        switch values[key] {
        case .string(let string): string
        case .int(let int): String(int)
        default: nil
        }
    }

    func required(_ key: String) throws -> String {
        guard let string = string(key) else { throw CommandError("Give \(key).") }
        return string
    }

    func int(_ key: String) throws -> Int? {
        guard let value = values[key], value != .null else { return nil }
        guard let int = value.int else { throw CommandError("\(key) is a line's number.") }
        return int
    }

    func bool(_ key: String) -> Bool? {
        values[key]?.bool
    }

    func page(_ key: String = "page") throws -> PageReference {
        try PageReference(required(key))
    }

    func ifVersion() -> String? {
        string("if_version")
    }

    /// Lines from start_line to end_line, or start_line alone.
    func lines() throws -> LineRange {
        guard let first = try int("start_line") else { throw CommandError("Give start_line.") }
        return LineRange(first, try int("end_line"))
    }

    /// Where lines go: after_line, or before_line, or else `fallback`.
    func position(or fallback: LinePosition) throws -> LinePosition {
        if let after = try int("after_line") { return .after(after) }
        if let before = try int("before_line") { return .before(before) }
        return fallback
    }
}

/// A tool the server offers, and the command each call to it is.
struct Tool: Sendable {
    let name: String
    let title: String
    let description: String
    let properties: [String: JSONValue]
    let required: [String]
    /// Whether it only reads, whether what it does can't be had back but by undoing it, and
    /// whether doing it twice does no more than once: for the app to decide what to ask about.
    let readOnly: Bool
    let destructive: Bool
    let idempotent: Bool
    let command: @Sendable (Arguments) throws -> PageCommand

    var json: JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })],
            "annotations": ["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                            "idempotentHint": .bool(idempotent), "openWorldHint": false],
        ]
    }
}

extension MCPServer {
    static var tools: [Tool] {
        let page: JSONValue = ["type": "string", "description": "The page: its colour (\(PageReference.colours)), its number from 1 to \(DotPalette.count), or \"current\" for the page Bite shows."]
        let markdown: JSONValue = ["type": "string", "description": "Markdown, a line of it for each line on the page."]
        let ifVersion: JSONValue = ["type": "string", "description": "The page's version as read. If the page has changed since, nothing is changed, to read it again."]
        let startLine: JSONValue = ["type": "integer", "description": "The first line, counting from 1."]
        let endLine: JSONValue = ["type": "integer", "description": "The last line, if more than one."]
        let afterLine: JSONValue = ["type": "integer", "description": "The line they go after; 0 for the start of the page."]
        let beforeLine: JSONValue = ["type": "integer", "description": "The line they go before, instead."]
        return [
            Tool(name: "list_pages", title: "List Pages",
                 description: "Lists Bite's seven pages: each one's number and colour, its title (its first line), how many lines it has, when it last changed, and which page Bite shows.",
                 properties: [:], required: [], readOnly: true, destructive: false, idempotent: true) { _ in .list },
            Tool(name: "read_page", title: "Read Page",
                 description: "Reads a page: its Markdown, each line numbered from 1, and its version, to pass as if_version when changing its lines.",
                 properties: ["page": page], required: ["page"], readOnly: true, destructive: false, idempotent: true) { arguments in
                .read(try arguments.page())
            },
            Tool(name: "search_pages", title: "Search Pages",
                 description: "Finds the lines saying some text, whatever its capitals and accents, on every page or on one, each with its page and line number.",
                 properties: ["query": ["type": "string", "description": "The text to look for."],
                              "page": ["type": "string", "description": "A page to look on alone; every page if not given."]],
                 required: ["query"], readOnly: true, destructive: false, idempotent: true) { arguments in
                .search(try arguments.required("query"), page: try arguments.string("page").map(PageReference.init))
            },
            Tool(name: "list_todos", title: "List To-Dos",
                 description: "Lists the to-dos left on every page or on one, each with its page and line; with include_done, the ticked-off ones too.",
                 properties: ["page": ["type": "string", "description": "A page to list alone; every page if not given."],
                              "include_done": ["type": "boolean", "description": "List the to-dos ticked off too."]],
                 required: [], readOnly: true, destructive: false, idempotent: true) { arguments in
                .toDos(page: try arguments.string("page").map(PageReference.init), done: arguments.bool("include_done") ?? false)
            },
            Tool(name: "page_statistics", title: "Page Statistics",
                 description: "Counts a page's words, characters and paragraphs, and says when it last changed.",
                 properties: ["page": page], required: ["page"], readOnly: true, destructive: false, idempotent: true) { arguments in
                .statistics(try arguments.page())
            },
            Tool(name: "add_to_page", title: "Add to Page",
                 description: "Adds lines at the end of a page, as if typed there: an empty last line takes the first of them.",
                 properties: ["page": page, "markdown": markdown, "if_version": ifVersion], required: ["page", "markdown"],
                 readOnly: false, destructive: false, idempotent: false) { arguments in
                .add(try arguments.page(), text: try arguments.required("markdown"), asToDo: false, ifVersion: arguments.ifVersion())
            },
            Tool(name: "add_todos", title: "Add To-Dos",
                 description: "Adds to-dos at the end of a page, one for each item.",
                 properties: ["page": page, "items": ["type": "array", "items": ["type": "string"], "description": "What each to-do says."],
                              "if_version": ifVersion],
                 required: ["page", "items"], readOnly: false, destructive: false, idempotent: false) { arguments in
                let items: [String] = switch arguments.values["items"] {
                case .array(let items): items.compactMap(\.string)
                case .string(let text): [text]
                default: []
                }
                return .add(try arguments.page(), text: items.joined(separator: "\n"), asToDo: true, ifVersion: arguments.ifVersion())
            },
            Tool(name: "insert_lines", title: "Insert Lines",
                 description: "Puts lines in a page after a line, or before one; after_line 0 puts them at the start, and with neither they go at the end.",
                 properties: ["page": page, "markdown": markdown, "after_line": afterLine, "before_line": beforeLine, "if_version": ifVersion],
                 required: ["page", "markdown"], readOnly: false, destructive: false, idempotent: false) { arguments in
                .insert(try arguments.page(), text: try arguments.required("markdown"), at: try arguments.position(or: .end), ifVersion: arguments.ifVersion())
            },
            Tool(name: "replace_lines", title: "Replace Lines",
                 description: "Replaces a line, or a run of lines, with new Markdown, which can be more lines or fewer.",
                 properties: ["page": page, "start_line": startLine, "end_line": endLine, "markdown": markdown, "if_version": ifVersion],
                 required: ["page", "start_line", "markdown"], readOnly: false, destructive: true, idempotent: false) { arguments in
                .replace(try arguments.page(), lines: try arguments.lines(), text: try arguments.required("markdown"), ifVersion: arguments.ifVersion())
            },
            Tool(name: "delete_lines", title: "Delete Lines",
                 description: "Deletes a line, or a run of lines.",
                 properties: ["page": page, "start_line": startLine, "end_line": endLine, "if_version": ifVersion],
                 required: ["page", "start_line"], readOnly: false, destructive: true, idempotent: false) { arguments in
                .delete(try arguments.page(), lines: try arguments.lines(), ifVersion: arguments.ifVersion())
            },
            Tool(name: "move_lines", title: "Move Lines",
                 description: "Moves lines on their page, or onto another: after a line there, or before one (after_line 0 for the start); with neither, to the end.",
                 properties: ["page": page, "start_line": startLine, "end_line": endLine,
                              "to_page": ["type": "string", "description": "The page to move them to, if not their own."],
                              "after_line": afterLine, "before_line": beforeLine, "if_version": ifVersion],
                 required: ["page", "start_line"], readOnly: false, destructive: true, idempotent: false) { arguments in
                let destination = try arguments.string("to_page").map(PageReference.init)
                return .move(try arguments.page(), lines: try arguments.lines(), to: destination,
                             at: try arguments.position(or: .end), ifVersion: arguments.ifVersion())
            },
            Tool(name: "find_and_replace", title: "Find and Replace",
                 description: "Replaces text on a page. Unless all is true, the text must be on the page once: give enough of it to be found only where meant.",
                 properties: ["page": page, "find": ["type": "string", "description": "The text as it is now."],
                              "replace": ["type": "string", "description": "What to put instead."],
                              "all": ["type": "boolean", "description": "Replace it wherever it is on the page."], "if_version": ifVersion],
                 required: ["page", "find", "replace"], readOnly: false, destructive: true, idempotent: false) { arguments in
                .findAndReplace(try arguments.page(), find: try arguments.required("find"), replacement: try arguments.required("replace"),
                                all: arguments.bool("all") ?? false, ifVersion: arguments.ifVersion())
            },
            Tool(name: "set_todo", title: "Tick To-Do",
                 description: "Ticks a to-do off (done true), or on again (done false): the one on a line, or the one saying some text.",
                 properties: ["page": page, "line": ["type": "integer", "description": "The to-do's line."],
                              "text": ["type": "string", "description": "What the to-do says, instead of its line."],
                              "done": ["type": "boolean", "description": "Whether it's done."], "if_version": ifVersion],
                 required: ["page", "done"], readOnly: false, destructive: true, idempotent: true) { arguments in
                let target: ToDoTarget
                if let line = try arguments.int("line") {
                    target = .line(line)
                } else if let text = arguments.string("text") {
                    target = .text(text)
                } else {
                    throw CommandError("Give the to-do's line, or what it says.")
                }
                return .setToDo(try arguments.page(), target, done: arguments.bool("done") ?? true, ifVersion: arguments.ifVersion())
            },
            Tool(name: "write_page", title: "Write Page",
                 description: "Replaces a page's whole text. Read it first, and pass its version as if_version.",
                 properties: ["page": page, "markdown": markdown, "if_version": ifVersion], required: ["page", "markdown"],
                 readOnly: false, destructive: true, idempotent: true) { arguments in
                .write(try arguments.page(), text: try arguments.required("markdown"), ifVersion: arguments.ifVersion())
            },
            Tool(name: "clear_page", title: "Clear Page",
                 description: "Empties a page.",
                 properties: ["page": page, "if_version": ifVersion], required: ["page"],
                 readOnly: false, destructive: true, idempotent: true) { arguments in
                .clear(try arguments.page(), ifVersion: arguments.ifVersion())
            },
            Tool(name: "open_page", title: "Open Page",
                 description: "Shows a page in Bite: on a Mac, its panel comes up on that page.",
                 properties: ["page": page], required: ["page"], readOnly: true, destructive: false, idempotent: true) { arguments in
                .open(try arguments.page())
            },
        ]
    }
}
