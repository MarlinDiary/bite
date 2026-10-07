import Testing
@testable import BiteCommands

/// Bite's pages for AI apps, over the Model Context Protocol.
struct MCPServerTests {
    private let groceries = "# Groceries\n- [ ] Milk\n- [x] Eggs\n"

    private func server(_ pages: FakePages = FakePages()) -> MCPServer<FakePages> {
        MCPServer(access: pages, version: "1.0")
    }

    private func reply(_ server: MCPServer<FakePages>, _ message: JSONValue) async throws -> JSONValue {
        let line = try #require(await server.reply(to: message.encoded()))
        return try #require(JSONValue(parsing: line))
    }

    @Test func itStartsInTheVersionAsked() async throws {
        let server = server()
        let reply = try await reply(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                             "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "Test", "version": "1"]]])
        #expect(reply["id"] == 1)
        #expect(reply["result"]?["protocolVersion"] == "2025-06-18")
        #expect(reply["result"]?["serverInfo"]?["name"] == "bite")
        #expect(reply["result"]?["capabilities"]?["tools"] != nil)
        #expect(reply["result"]?["instructions"]?.string?.contains("4 purple") == true)
        // One it doesn't know, in its own newest.
        let newer = try await self.reply(server, ["jsonrpc": "2.0", "id": "a", "method": "initialize", "params": ["protocolVersion": "2099-01-01"]])
        #expect(newer["id"] == "a")
        #expect(newer["result"]?["protocolVersion"] == .string(MCPServer<FakePages>.protocolVersions[0]))
    }

    @Test func notificationsGetNoReply() async {
        let server = server()
        #expect(await server.reply(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(await server.reply(to: "") == nil)
    }

    @Test func mistakesGetErrors() async throws {
        let server = server()
        let line = try #require(await server.reply(to: "{nope"))
        let notJSON = try #require(JSONValue(parsing: line))
        #expect(notJSON["error"]?["code"] == -32700)
        let unknown = try await reply(server, ["jsonrpc": "2.0", "id": 2, "method": "resources/read"])
        #expect(unknown["error"]?["code"] == -32601)
        let noTool = try await reply(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "fly", "arguments": [:]]])
        #expect(noTool["error"]?["code"] == -32602)
        let ping = try await reply(server, ["jsonrpc": "2.0", "id": 4, "method": "ping"])
        #expect(ping["result"] == [:])
    }

    @Test func everyToolIsListedWithWhatItTakes() async throws {
        let reply = try await reply(server(), ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        guard case .array(let tools) = reply["result"]?["tools"] else { Issue.record("No tools"); return }
        let names = tools.compactMap { $0["name"]?.string }
        #expect(names == ["list_pages", "read_page", "search_pages", "list_todos", "page_statistics", "add_to_page", "add_todos", "insert_lines",
                          "replace_lines", "delete_lines", "move_lines", "find_and_replace", "set_todo", "write_page", "clear_page", "open_page"])
        for tool in tools {
            #expect(tool["inputSchema"]?["type"] == "object")
            #expect(tool["description"]?.string?.isEmpty == false)
            #expect(tool["annotations"]?["readOnlyHint"] != nil)
        }
        let delete = try #require(tools.first { $0["name"] == "delete_lines" })
        #expect(delete["annotations"]?["destructiveHint"] == true)
        #expect(delete["inputSchema"]?["required"] == ["page", "start_line"])
    }

    @Test func toolsReadAndChangeThePages() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let server = server(pages)
        let read = try await reply(server, ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                            "params": ["name": "read_page", "arguments": ["page": "purple"]]])
        #expect(read["result"]?["isError"] == false)
        let text = try #require(read["result"]?["content"]?.arrayFirst?["text"]?.string)
        #expect(text.contains("2  - [ ] Milk"))

        let version = PageLines.version(of: groceries)
        let ticked = try await reply(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                                              "params": ["name": "set_todo", "arguments": ["page": 4, "line": 2, "done": true, "if_version": .string(version)]]])
        #expect(ticked["result"]?["isError"] == false)
        #expect(await pages.markdown[3] == "# Groceries\n- [x] Milk\n- [x] Eggs\n")

        let added = try await reply(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                             "params": ["name": "add_todos", "arguments": ["page": "purple", "items": ["Bread", "Butter"]]]])
        #expect(added["result"]?["isError"] == false)
        #expect(await pages.markdown[3] == "# Groceries\n- [x] Milk\n- [x] Eggs\n- [ ] Bread\n- [ ] Butter\n")

        let moved = try await reply(server, ["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                                             "params": ["name": "move_lines", "arguments": ["page": "purple", "start_line": 4, "end_line": 5, "after_line": 1]]])
        #expect(moved["result"]?["isError"] == false)
        #expect(await pages.markdown[3] == "# Groceries\n- [ ] Bread\n- [ ] Butter\n- [x] Milk\n- [x] Eggs\n")
    }

    /// What went wrong is the tool's answer, for the AI to put right, not the protocol's error.
    @Test func aToolsMistakeIsItsAnswer() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let reply = try await reply(server(pages), ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                                                    "params": ["name": "delete_lines", "arguments": ["page": "purple", "start_line": 9]]])
        #expect(reply["result"]?["isError"] == true)
        #expect(reply["result"]?["content"]?.arrayFirst?["text"]?.string?.contains("has 3 lines") == true)
        #expect(await pages.markdown[3] == groceries)
    }
}

extension JSONValue {
    var arrayFirst: JSONValue? {
        if case .array(let array) = self { array.first } else { nil }
    }
}
