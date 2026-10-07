import Testing
@testable import BiteCommands

/// The `bite` command's words.
struct CommandLineTests {
    private func parse(_ line: String, input: String? = nil) throws -> CommandLineInterface.Request {
        try CommandLineInterface.parse(line.split(separator: " ").map(String.init), input: { input })
    }

    private func command(_ arguments: [String], input: String? = nil) throws -> PageCommand? {
        guard case .command(let command, _, _) = try CommandLineInterface.parse(arguments, input: { input }) else { return nil }
        return command
    }

    @Test func helpVersionAndTheServer() throws {
        #expect(try parse("") == .help)
        #expect(try parse("help") == .help)
        #expect(try parse("--help") == .help)
        #expect(try parse("--version") == .version)
        #expect(try parse("mcp") == .mcp)
    }

    @Test func readingCommands() throws {
        #expect(try parse("list --json") == .command(.list, json: true, numbered: false))
        #expect(try parse("read purple -n") == .command(.read(.page(3)), json: false, numbered: true))
        #expect(try parse("read current") == .command(.read(.shown), json: false, numbered: false))
        #expect(try command(["search", "oat", "milk", "--page", "4"]) == .search("oat milk", page: .page(3)))
        #expect(try command(["stats", "Teal"]) == .statistics(.page(5)))
    }

    @Test func toDosAreListedAndPagesExported() throws {
        #expect(try command(["todos"]) == .toDos(page: nil, done: false))
        #expect(try command(["todos", "purple", "--all"]) == .toDos(page: .page(3), done: true))
        #expect(try parse("export purple --pdf") == .export(.page(3), .pdf))
        #expect(try parse("export 2 --image") == .export(.page(1), .image))
        #expect(throws: CommandError.self) { try parse("export purple") }
        #expect(throws: CommandError.self) { try parse("export purple --pdf --image") }
    }

    @Test func textComesFromTheCommandLineOrPipedIn() throws {
        #expect(try command(["add", "purple", "Buy", "bread"]) == .add(.page(3), text: "Buy bread", asToDo: false, ifVersion: nil))
        #expect(try command(["add", "purple"], input: "# Notes\nOne\n") == .add(.page(3), text: "# Notes\nOne\n", asToDo: false, ifVersion: nil))
        #expect(try command(["todo", "1", "- [ ] Milk"]) == .add(.page(0), text: "- [ ] Milk", asToDo: true, ifVersion: nil))
        #expect(throws: CommandError.self) { try command(["add", "purple"]) }
    }

    @Test func changesByLine() throws {
        #expect(try command(["insert", "purple", "## Dairy", "--after", "1"]) == .insert(.page(3), text: "## Dairy", at: .after(1), ifVersion: nil))
        #expect(try command(["insert", "purple", "Top", "--start"]) == .insert(.page(3), text: "Top", at: .start, ifVersion: nil))
        #expect(try command(["insert", "purple", "Last"]) == .insert(.page(3), text: "Last", at: .end, ifVersion: nil))
        #expect(try command(["replace", "purple", "2-3", "New", "--if-version", "abc"]) == .replace(.page(3), lines: LineRange(2, 3), text: "New", ifVersion: "abc"))
        #expect(try command(["delete", "purple", "4", "--if-version=abc"]) == .delete(.page(3), lines: LineRange(4), ifVersion: "abc"))
        #expect(try command(["move", "purple", "2-3", "--before", "1"]) == .move(.page(3), lines: LineRange(2, 3), to: nil, at: .before(1), ifVersion: nil))
        #expect(try command(["move", "purple", "2", "--to", "green"]) == .move(.page(3), lines: LineRange(2), to: .page(6), at: .end, ifVersion: nil))
        // Moved on its own page, it needs telling where.
        #expect(throws: CommandError.self) { try command(["move", "purple", "2"]) }
        #expect(throws: CommandError.self) { try command(["insert", "purple", "Top", "--start", "--end"]) }
    }

    @Test func textToDosAndWholePages() throws {
        #expect(try command(["find-replace", "purple", "Milk", "Oat milk", "--all"]) == .findAndReplace(.page(3), find: "Milk", replacement: "Oat milk", all: true, ifVersion: nil))
        #expect(try command(["tick", "purple", "3"]) == .setToDo(.page(3), .line(3), done: true, ifVersion: nil))
        #expect(try command(["untick", "purple", "oat", "milk"]) == .setToDo(.page(3), .text("oat milk"), done: false, ifVersion: nil))
        #expect(try command(["write", "red"], input: "# Plan\n") == .write(.page(2), text: "# Plan\n", ifVersion: nil))
        #expect(try command(["clear", "red"]) == .clear(.page(2), ifVersion: nil))
        #expect(try command(["open", "7"]) == .open(.page(6)))
    }

    /// A list item's dash isn't an option.
    @Test func textCanStartWithADash() throws {
        #expect(try command(["add", "purple", "- [ ] Milk"]) == .add(.page(3), text: "- [ ] Milk", asToDo: false, ifVersion: nil))
        #expect(try command(["add", "purple", "--", "--all", "of it"]) == .add(.page(3), text: "--all of it", asToDo: false, ifVersion: nil))
    }

    /// Help says how an AI app adds the server, with where the tool is.
    @Test func helpSaysHowAnAIAppAddsTheServer() {
        let help = CommandLineInterface.usage(tool: "/Applications/Bite.app/Contents/Helpers/bite")
        #expect(help.hasPrefix("bite reads and changes Bite's pages"))
        #expect(help.contains("claude mcp add --scope user bite -- /Applications/Bite.app/Contents/Helpers/bite mcp"))
        #expect(help.contains(#"{"command": "/Applications/Bite.app/Contents/Helpers/bite", "args": ["mcp"]}"#))
        #expect(CommandLineInterface.usage(tool: "/Users/sam/My Apps/bite").contains("-- '/Users/sam/My Apps/bite' mcp"))
    }

    @Test func mistakesAreSaid() throws {
        #expect(throws: CommandError.self) { try parse("fly purple") }
        #expect(throws: CommandError.self) { try parse("read") }
        #expect(throws: CommandError.self) { try parse("read magenta") }
        #expect(throws: CommandError.self) { try parse("read purple --colour") }
        #expect(throws: CommandError.self) { try parse("read purple extra") }
        #expect(throws: CommandError.self) { try parse("delete purple") }
        #expect(throws: CommandError.self) { try parse("insert purple Top --after") }
    }
}
