import Foundation
import Testing
import BiteKit
@testable import BiteCommands

/// Bite's pages as the tests' own, Bite taking each change in as it does one left for it: put
/// together with whatever changed on the page since it was read.
actor FakePages: PageAccess {
    var markdown: [String]
    var modifiedDates: [Date?]
    var shown: Int?
    /// Whether Bite is running to take changes in.
    var takes = true
    var opened: [Int] = []
    var changes: [(page: Int, before: String, after: String)] = []
    /// Typing in Bite after the tool read the page, before its change went in.
    var typedMeanwhile: (page: Int, markdown: String)?

    init(_ markdown: [String] = Array(repeating: "", count: 7), shown: Int? = 0) {
        self.markdown = markdown
        modifiedDates = Array(repeating: nil, count: markdown.count)
        self.shown = shown
    }

    func setPage(_ page: Int, _ text: String) {
        markdown[page] = text
    }

    func setModified(_ page: Int, _ date: Date?) {
        modifiedDates[page] = date
    }

    func setTakes(_ takes: Bool) {
        self.takes = takes
    }

    func setTypedMeanwhile(_ page: Int, _ text: String) {
        typedMeanwhile = (page, text)
    }

    func pages() -> [String] {
        markdown
    }

    func modified() -> [Date?] {
        modifiedDates
    }

    func shownPage() -> Int? {
        shown
    }

    func change(page: Int, from before: String, to after: String) -> String? {
        changes.append((page, before, after))
        if let typed = typedMeanwhile, typed.page == page {
            markdown[page] = typed.markdown
            typedMeanwhile = nil
        }
        guard takes else { return nil }
        markdown[page] = PageShare(page: page, before: before, after: after).applied(to: markdown[page])
        return markdown[page]
    }

    func open(page: Int) {
        opened.append(page)
    }
}

struct PageCommandTests {
    private let groceries = "# Groceries\n- [ ] Milk\n- [x] Eggs\n"

    @Test func theListSaysEachPageAndWhichIsShown() async throws {
        let pages = FakePages(["# Welcome\nHi\n", "", "", groceries, "", "", ""], shown: 3)
        let result = try await PageCommand.list.run(on: pages)
        let rows = result.text.split(separator: "\n")
        #expect(rows.count == 8)
        #expect(rows[1] == "1 yellow: \"Welcome\", 2 lines")
        #expect(rows[2] == "2 orange: empty")
        #expect(rows[4] == "4 purple (shown): \"Groceries\", 3 lines, 1 to-do left of 2")
        guard case .array(let json) = result.json else { Issue.record("Not a list"); return }
        #expect(json[3]["color"] == "purple")
        #expect(json[3]["shown"] == true)
        #expect(json[1]["empty"] == true)
        #expect(json[3]["todos"] == ["left": 1, "done": 1])
    }

    @Test func theToDosLeftAreListedOnEveryPageOrOne() async throws {
        let pages = FakePages(["- [ ] Call Sam\n", "", "", groceries, "", "", ""])
        let left = try await PageCommand.toDos(page: nil, done: false).run(on: pages)
        #expect(left.text == "2 to-dos left on Bite's pages:\nyellow 1: Call Sam\npurple 2: Milk")
        let all = try await PageCommand.toDos(page: .page(3), done: true).run(on: pages)
        #expect(all.text == "2 to-dos on the purple page:\npurple 2: [ ] Milk\npurple 3: [x] Eggs")
        let none = try await PageCommand.toDos(page: .page(1), done: false).run(on: pages)
        #expect(none.text == "No to-dos left on the orange page.")
        guard case .array(let json) = all.json else { Issue.record("Not a list"); return }
        #expect(json[1]["done"] == true)
        #expect(json[1]["line"] == 3)
    }

    @Test func aPageIsReadNumberedWithItsVersion() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let result = try await PageCommand.read(.page(3)).run(on: pages)
        let version = PageLines.version(of: groceries)
        #expect(result.text == "The purple page (4), version \(version), 3 lines:\n1  # Groceries\n2  - [ ] Milk\n3  - [x] Eggs")
        #expect(result.markdown == groceries)
        #expect(result.json["title"] == "Groceries")
        #expect(result.json["version"] == .string(version))
        let empty = try await PageCommand.read(.page(0)).run(on: pages)
        #expect(empty.text.hasPrefix("The yellow page (1) is empty"))
    }

    @Test func thePageShownIsCurrent() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""], shown: 3)
        #expect(try await PageCommand.read(.shown).run(on: pages).markdown == groceries)
        #expect(try PageReference("Purple") == .page(3))
        #expect(try PageReference("4") == .page(3))
        #expect(try PageReference("current") == .shown)
        #expect(throws: CommandError.self) { try PageReference("8") }
        #expect(throws: CommandError.self) { try PageReference("magenta") }
    }

    @Test func linesAreFoundOnEveryPageOrOne() async throws {
        let pages = FakePages(["Milk and honey\n", "", "", groceries, "", "", ""])
        let everywhere = try await PageCommand.search("milk", page: nil).run(on: pages)
        #expect(everywhere.text == "2 lines on Bite's pages say \"milk\":\nyellow 1: Milk and honey\npurple 2: - [ ] Milk")
        let one = try await PageCommand.search("milk", page: .page(3)).run(on: pages)
        #expect(one.text == "1 line on the purple page says \"milk\":\npurple 2: - [ ] Milk")
        let none = try await PageCommand.search("bread", page: nil).run(on: pages)
        #expect(none.text == "Nothing on Bite's pages says \"bread\".")
    }

    @Test func statisticsCountThePage() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let result = try await PageCommand.statistics(.page(3)).run(on: pages)
        #expect(result.json["words"] == 3)
        #expect(result.json["paragraphs"] == 3)
        #expect(result.text == "The purple page has 3 words, 17 characters and 3 paragraphs.")
    }

    /// When a page changed, said as a person would: a moment ago is just now.
    @Test func whenAPageChangedIsSaidAsAPersonWould() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        await pages.setModified(3, now.addingTimeInterval(-20))
        let moment = try await PageCommand.statistics(.page(3)).run(on: pages, now: now)
        #expect(moment.text.hasSuffix("and changed just now."))
        await pages.setModified(3, now.addingTimeInterval(-2 * 3600))
        let hours = try await PageCommand.list.run(on: pages, now: now)
        #expect(hours.text.contains("4 purple: \"Groceries\", 3 lines, 1 to-do left of 2, changed 2 hours ago"))
    }

    @Test func linesAddedGoAtTheEndAnEmptyLastLineTakingThem() async throws {
        let pages = FakePages(["", "", "", groceries + "\n", "", "", ""])
        let result = try await PageCommand.add(.page(3), text: "- [ ] Bread\n- [ ] Butter", asToDo: false, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == groceries + "- [ ] Bread\n- [ ] Butter\n")
        #expect(result.text.hasPrefix("Added 2 lines at the end. The purple page now has 5 lines, version "))
        #expect(result.json["taken"] == true)
    }

    @Test func toDosAddedAreBoxesWhateverTheyWereWritten() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        _ = try await PageCommand.add(.page(3), text: "Bread\n- Butter\n- [ ] Jam\n\n", asToDo: true, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == groceries + "- [ ] Bread\n- [ ] Butter\n- [ ] Jam\n")
    }

    @Test func linesGoWhereSaid() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        _ = try await PageCommand.insert(.page(3), text: "## Dairy", at: .after(1), ifVersion: nil).run(on: pages)
        _ = try await PageCommand.insert(.page(3), text: "Saturday", at: .start, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "Saturday\n# Groceries\n## Dairy\n- [ ] Milk\n- [x] Eggs\n")
        await #expect(throws: CommandError.self) {
            try await PageCommand.insert(.page(3), text: "Far off", at: .after(9), ifVersion: nil).run(on: pages)
        }
    }

    @Test func linesAreReplacedAndDeleted() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        _ = try await PageCommand.replace(.page(3), lines: LineRange(2), text: "- [ ] Oat milk\n- [ ] Honey", ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [ ] Oat milk\n- [ ] Honey\n- [x] Eggs\n")
        let result = try await PageCommand.delete(.page(3), lines: LineRange(3, 4), ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [ ] Oat milk\n")
        #expect(result.text.hasPrefix("Deleted lines 3 to 4."))
        await #expect(throws: CommandError.self) {
            try await PageCommand.delete(.page(3), lines: LineRange(5), ifVersion: nil).run(on: pages)
        }
    }

    @Test func linesMoveOnTheirPageAndOntoAnother() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", "Done\n"])
        _ = try await PageCommand.move(.page(3), lines: LineRange(3), to: nil, at: .after(1), ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [x] Eggs\n- [ ] Milk\n")
        let result = try await PageCommand.move(.page(3), lines: LineRange(2), to: .page(6), at: .end, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [ ] Milk\n")
        #expect(await pages.markdown[6] == "Done\n- [x] Eggs\n")
        // Put on the other page first, then taken off this one.
        #expect(await pages.changes.suffix(2).map(\.page) == [6, 3])
        #expect(result.json["from"]?["color"] == "purple")
        #expect(result.json["to"]?["color"] == "green")
    }

    @Test func textIsReplaced() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        _ = try await PageCommand.findAndReplace(.page(3), find: "Milk", replacement: "Oat milk", all: false, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [ ] Oat milk\n- [x] Eggs\n")
    }

    @Test func toDosAreTickedByLineOrByWhatTheySay() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let ticked = try await PageCommand.setToDo(.page(3), .text("milk"), done: true, ifVersion: nil).run(on: pages)
        #expect(ticked.text.hasPrefix("Ticked \"Milk\" off, on line 2."))
        _ = try await PageCommand.setToDo(.page(3), .line(3), done: false, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [x] Milk\n- [ ] Eggs\n")
        let again = try await PageCommand.setToDo(.page(3), .line(2), done: true, ifVersion: nil).run(on: pages)
        #expect(again.text == "Nothing to change: the purple page is that way already.")
        await #expect(throws: CommandError.self) {
            try await PageCommand.setToDo(.page(3), .line(1), done: true, ifVersion: nil).run(on: pages)
        }
    }

    @Test func aPageIsWrittenAndCleared() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        _ = try await PageCommand.write(.page(3), text: "# Plan\nRest", ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Plan\nRest\n")
        let cleared = try await PageCommand.clear(.page(3), ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "")
        #expect(cleared.text == "Cleared the page. The purple page is now empty, version \(PageLines.version(of: "")).")
    }

    /// A change by line numbers read before the page changed is left alone, to read the page again.
    @Test func aPageChangedSinceTheVersionReadIsLeftAlone() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        let read = PageLines.version(of: groceries)
        await pages.setPage(3, "# Groceries\n- [ ] Bread\n- [ ] Milk\n- [x] Eggs\n")
        await #expect(throws: CommandError.self) {
            try await PageCommand.delete(.page(3), lines: LineRange(2), ifVersion: read).run(on: pages)
        }
        #expect(await pages.changes.isEmpty)
        let now = PageLines.version(of: await pages.markdown[3])
        _ = try await PageCommand.delete(.page(3), lines: LineRange(2), ifVersion: now).run(on: pages)
        #expect(await pages.markdown[3] == groceries)
    }

    /// Typing in Bite meanwhile is kept: Bite puts the two together, line by line.
    @Test func typingMeanwhileIsKept() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        await pages.setTypedMeanwhile(3, "# Groceries\n- [ ] Milk\n- [x] Eggs\n- [ ] Bread\n")
        let result = try await PageCommand.setToDo(.page(3), .line(2), done: true, ifVersion: nil).run(on: pages)
        #expect(await pages.markdown[3] == "# Groceries\n- [x] Milk\n- [x] Eggs\n- [ ] Bread\n")
        #expect(result.text.hasSuffix("The purple page now has 4 lines, version \(PageLines.version(of: await pages.markdown[3]))."))
    }

    @Test func aChangeWaitsForBiteWhenItIsNotRunning() async throws {
        let pages = FakePages(["", "", "", groceries, "", "", ""])
        await pages.setTakes(false)
        let result = try await PageCommand.add(.page(3), text: "Bread", asToDo: true, ifVersion: nil).run(on: pages)
        #expect(result.text == "Added 1 to-do at the end. Bite isn't running, so the change waits on the purple page, to go in as Bite next runs.")
        #expect(result.json["taken"] == false)
    }

    @Test func aPageIsOpened() async throws {
        let pages = FakePages()
        let result = try await PageCommand.open(.page(5)).run(on: pages)
        #expect(await pages.opened == [5])
        #expect(result.text == "Bite shows the teal page.")
    }
}
