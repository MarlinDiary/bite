import Foundation
import BiteCommands

// `bite`: Bite's pages from the Terminal, and for AI apps as an MCP server. It comes in Bite, at
// Bite.app/Contents/Helpers/bite.

let pages = ShelfPages()
// Its own, or, run through a link, which leaves it without, the Bite it came in's.
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ShelfPages.biteVersion ?? "1.0"

/// Whatever's piped in, read when a command needs text it wasn't given: nothing when it's run at
/// the Terminal, the keyboard its input.
func pipedInput() -> String? {
    guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
}

func say(_ text: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
}

do {
    switch try CommandLineInterface.parse(Array(CommandLine.arguments.dropFirst()), input: pipedInput) {
    case .help:
        let tool = Bundle.main.executableURL?.resolvingSymlinksInPath().path(percentEncoded: false) ?? "bite"
        say(CommandLineInterface.usage(tool: tool))
    case .version:
        say("bite \(version)")
    case .mcp:
        // A message a line, each answered in turn, until the AI app closes the tool's input.
        let server = MCPServer(access: pages, version: version)
        for try await line in FileHandle.standardInput.bytes.lines {
            if let reply = await server.reply(to: line) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
            }
        }
    case .export(let reference, let format):
        // The page as Bite's Share makes it: a file, sent on to one with `>`.
        let read = try await PageCommand.read(reference).run(on: pages)
        guard let markdown = read.markdown, let number = read.json["page"]?.int else { throw CommandError("The page can't be read.") }
        let kind: PageExport.Format = switch format {
        case .pdf: .pdf
        case .image: .image
        case .markdown: .markdown
        }
        if kind != .markdown, isatty(FileHandle.standardOutput.fileDescriptor) != 0 {
            let file = "\(PageExport.name(page: number - 1, markdown: markdown)).\(kind.fileExtension)"
            let colour = read.json["color"]?.string ?? String(number)
            throw CommandError("Send it to a file: bite export \(colour) --\(kind == .pdf ? "pdf" : "image") > \"\(file)\"")
        }
        guard let data = PageExport.data(kind, page: number - 1, markdown: markdown, scale: 2) else { throw CommandError("The page can't be drawn.") }
        FileHandle.standardOutput.write(data)
    case .command(let command, let json, let numbered):
        let result = try await command.run(on: pages)
        if json {
            say(result.json.encoded(pretty: true))
        } else if let markdown = result.markdown, !numbered {
            // A page read is its Markdown as it is, to go on to a file or another command.
            FileHandle.standardOutput.write(Data(markdown.utf8))
        } else {
            say(result.text)
        }
    }
} catch let error as CommandError {
    say("bite: \(error.message)", to: .standardError)
    exit(1)
} catch {
    say("bite: \(error.localizedDescription)", to: .standardError)
    exit(1)
}
