import Foundation
import BiteKit

/// The `bite` command's words: what's asked for, read from the command line.
public enum CommandLineInterface {
    public enum Request: Equatable, Sendable {
        case help
        case version
        /// Runs as an MCP server for AI apps (see `MCPServer`).
        case mcp
        case command(PageCommand, json: Bool, numbered: Bool)
        /// A page as a file, as Bite's Share makes one, to standard output.
        case export(PageReference, ExportFormat)
    }

    public enum ExportFormat: Equatable, Sendable {
        case pdf, image, markdown
    }

    /// What `arguments`, the command line after `bite`, ask for. Text not on the command line comes
    /// from `input`, standard input when something's piped in, nil otherwise.
    public static func parse(_ arguments: [String], input: () -> String?) throws -> Request {
        var words = Words(arguments)
        try words.read()
        guard let name = words.positional.first else { return .help }
        var rest = Array(words.positional.dropFirst())
        let ifVersion = words.options["--if-version"]
        let json = words.has("--json")
        var command = PageCommand.list

        func page() throws -> PageReference {
            guard !rest.isEmpty else { throw CommandError("Name the page: by its colour (\(PageReference.colours)), its number, or \"current\".") }
            return try PageReference(rest.removeFirst())
        }
        func lines() throws -> LineRange {
            guard !rest.isEmpty else { throw CommandError("Give the line, or lines, as 3 or 3-5.") }
            return try LineRange(parsing: rest.removeFirst())
        }
        func text(_ what: String) throws -> String {
            if !rest.isEmpty { return rest.joined(separator: " ") }
            guard let piped = input() else { throw CommandError("Give the \(what), or pipe it in.") }
            return piped
        }
        func position(or fallback: LinePosition?) throws -> LinePosition {
            var positions: [LinePosition] = []
            if let after = words.options["--after"] { positions.append(.after(try number(after))) }
            if let before = words.options["--before"] { positions.append(.before(try number(before))) }
            if words.has("--start") { positions.append(.start) }
            if words.has("--end") { positions.append(.end) }
            guard positions.count <= 1 else { throw CommandError("Say only one of --after, --before, --start and --end.") }
            guard let position = positions.first ?? fallback else { throw CommandError("Say where: --after N, --before N, --start or --end.") }
            return position
        }
        func done() throws -> Request {
            guard rest.isEmpty else { throw CommandError("\"\(rest.joined(separator: " "))\" is more than \(name) takes. See bite help.") }
            return .command(command, json: json, numbered: words.has("-n") || words.has("--numbered"))
        }

        switch name {
        case "help", "-h", "--help":
            return .help
        case "version", "--version":
            return .version
        case "mcp":
            return .mcp
        case "list", "pages":
            command = .list
        case "read", "show", "cat":
            command = .read(try page())
        case "search", "find", "grep":
            let reference = try words.options["--page"].map(PageReference.init)
            command = .search(try text("text to look for"), page: reference)
            rest = []
        case "stats", "statistics":
            command = .statistics(try page())
        case "add", "append":
            let reference = try page()
            command = .add(reference, text: try text("text to add"), asToDo: false, ifVersion: ifVersion)
            rest = []
        case "todo":
            let reference = try page()
            command = .add(reference, text: try text("to-do"), asToDo: true, ifVersion: ifVersion)
            rest = []
        case "todos":
            command = .toDos(page: rest.isEmpty ? nil : try page(), done: words.has("--all"))
        case "export":
            let reference = try page()
            let named: [(String, ExportFormat)] = [("--pdf", .pdf), ("--image", .image), ("--markdown", .markdown)]
            let formats = named.filter { words.has($0.0) }.map(\.1)
            guard formats.count == 1 else { throw CommandError("Say one of --pdf, --image and --markdown.") }
            guard rest.isEmpty else { throw CommandError("\"\(rest.joined(separator: " "))\" is more than export takes. See bite help.") }
            return .export(reference, formats[0])
        case "insert":
            let reference = try page()
            command = .insert(reference, text: try text("text to put in"), at: try position(or: .end), ifVersion: ifVersion)
            rest = []
        case "replace":
            let reference = try page()
            let range = try lines()
            command = .replace(reference, lines: range, text: try text("new text"), ifVersion: ifVersion)
            rest = []
        case "delete", "remove":
            command = .delete(try page(), lines: try lines(), ifVersion: ifVersion)
        case "move":
            let reference = try page()
            let range = try lines()
            let destination = try words.options["--to"].map(PageReference.init)
            command = .move(reference, lines: range, to: destination, at: try position(or: destination == nil ? nil : .end), ifVersion: ifVersion)
        case "find-replace", "replace-text":
            let reference = try page()
            guard rest.count == 2 else { throw CommandError("Give the text to find and what to put instead, each in quotes.") }
            command = .findAndReplace(reference, find: rest[0], replacement: rest[1], all: words.has("--all"), ifVersion: ifVersion)
            rest = []
        case "tick", "untick", "check", "uncheck":
            let reference = try page()
            let target: ToDoTarget
            if rest.count == 1, let line = Int(rest[0]) {
                target = .line(line)
                rest = []
            } else {
                target = .text(try text("to-do's line or text"))
                rest = []
            }
            command = .setToDo(reference, target, done: name == "tick" || name == "check", ifVersion: ifVersion)
        case "write":
            let reference = try page()
            command = .write(reference, text: try text("page's new text"), ifVersion: ifVersion)
            rest = []
        case "clear":
            command = .clear(try page(), ifVersion: ifVersion)
        case "open":
            command = .open(try page())
        default:
            throw CommandError("bite has no command \"\(name)\". See bite help.")
        }
        return try done()
    }

    private static func number(_ text: String) throws -> Int {
        guard let number = Int(text) else { throw CommandError("\"\(text)\" isn't a line's number.") }
        return number
    }

    /// The command line, its options apart.
    private struct Words {
        var arguments: [String]
        var positional: [String] = []
        var options: [String: String] = [:]
        var switches: Set<String> = []

        static let valued: Set<String> = ["--if-version", "--after", "--before", "--to", "--page"]
        static let flags: Set<String> = ["--json", "-n", "--numbered", "--start", "--end", "--all", "--pdf", "--image", "--markdown"]

        init(_ arguments: [String]) {
            self.arguments = arguments
        }

        mutating func read() throws {
            var index = 0
            while index < arguments.count {
                let word = arguments[index]
                index += 1
                if word == "--" {
                    positional += arguments[index...]
                    break
                }
                let (name, attached) = word.hasPrefix("--") && word.contains("=")
                    ? (String(word.prefix { $0 != "=" }), String(word.drop { $0 != "=" }.dropFirst()))
                    : (word, nil)
                if Self.valued.contains(name) {
                    guard let value = attached ?? (index < arguments.count ? arguments[index] : nil) else {
                        throw CommandError("\(name) needs a value after it.")
                    }
                    if attached == nil { index += 1 }
                    options[name] = value
                } else if Self.flags.contains(word) {
                    switches.insert(word)
                } else if word.hasPrefix("--"), word.count > 2, !["--help", "--version"].contains(word) {
                    throw CommandError("bite has no option \(word). See bite help.")
                } else {
                    positional.append(word)
                }
            }
        }

        func has(_ flag: String) -> Bool {
            switches.contains(flag)
        }
    }

    /// What `bite help` says, `tool` being where the tool is, for an AI app's settings.
    public static func usage(tool: String) -> String {
        let shell = tool.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-".contains($0)) }
            ? tool : "'" + tool.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let json = tool.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return usage + """


        An AI app adds bite's MCP server once. Claude Code, for one, from Terminal:
          claude mcp add --scope user bite -- \(shell) mcp
        In another app's MCP servers: {"command": "\(json)", "args": ["mcp"]}
        """
    }

    static let usage = """
    bite reads and changes Bite's pages, from the Terminal or for an AI.

    Name a page by its colour (\(PageReference.colours)), its number from 1 to \(DotPalette.count),
    or "current" for the page Bite shows. Pages are Markdown, a line of it for each line on the page.

      bite list                              Each page: its title, lines, and when it changed
      bite read PAGE [-n]                    The page's Markdown; -n numbers its lines
      bite search TEXT [--page PAGE]         The lines saying TEXT, on every page or one
      bite stats PAGE                        Its words, characters and paragraphs
      bite todos [PAGE] [--all]              The to-dos left, or --all of them, on every page or one

      bite add PAGE [TEXT]                   Adds lines at the end, as if typed there
      bite todo PAGE [TEXT]                  Adds to-dos at the end, one a line
      bite insert PAGE [TEXT] (--after N | --before N | --start | --end)
      bite replace PAGE LINES [TEXT]         Replaces line N, or lines N-M
      bite delete PAGE LINES
      bite move PAGE LINES (--after N | --before N | --start | --end) [--to PAGE]
      bite find-replace PAGE FIND REPLACEMENT [--all]
      bite tick PAGE (LINE | TEXT)           Ticks a to-do off
      bite untick PAGE (LINE | TEXT)         Ticks it on again
      bite write PAGE [TEXT]                 Replaces the whole page
      bite clear PAGE
      bite open PAGE                         Shows the page in Bite
      bite export PAGE (--pdf | --image | --markdown) > FILE
                                             The page as a file, as Bite's Share makes it

      bite mcp                               Runs as an MCP server, for AI apps

    TEXT can be piped in instead: bite add purple < notes.md
    Lines changed by number can name the version read (bite read PAGE -n shows it) with
    --if-version V: a page changed since is left alone, to read again.
    --json gives any answer as JSON.

    Bite takes each change in as it would one typed there, put together with any typing since,
    and keeps it on your other devices through iCloud.
    """
}
