import Testing
@testable import BiteCommands

/// A page as numbered lines, as the command line tool shows and changes it.
struct PageLinesTests {
    @Test func aPageIsItsLinesEachEnded() {
        let page = PageLines("# Groceries\n- [ ] Milk\n")
        #expect(page.lines == ["# Groceries", "- [ ] Milk"])
        #expect(page.markdown == "# Groceries\n- [ ] Milk\n")
        // An empty last line on the page is a line of its own.
        #expect(PageLines("Notes\n\n").lines == ["Notes", ""])
        #expect(PageLines("Notes\n\n").markdown == "Notes\n\n")
        #expect(PageLines("No end").markdown == "No end\n")
    }

    @Test func anEmptyPageHasNoLines() {
        #expect(PageLines("").lines.isEmpty)
        #expect(PageLines("\n\n").lines.isEmpty)
        #expect(PageLines(lines: []).markdown == "")
    }

    @Test func linesGivenAreTheirLinesAnyLineBreaks() {
        #expect(PageLines.given("One\r\nTwo\rThree\n") == ["One", "Two", "Three"])
        #expect(PageLines.given("One\n\nTwo") == ["One", "", "Two"])
    }

    @Test func theVersionChangesWithThePage() {
        let version = PageLines.version(of: "# Groceries\n")
        #expect(version.count == 8)
        #expect(version == PageLines.version(of: "# Groceries\n"))
        #expect(version != PageLines.version(of: "# Groceries!\n"))
    }

    @Test func numberedLinesLineUp() {
        let page = PageLines(lines: (1...10).map { "Line \($0)" })
        let numbered = page.numbered().split(separator: "\n")
        #expect(numbered.first == " 1  Line 1")
        #expect(numbered.last == "10  Line 10")
    }

    @Test func linesAreFoundWhateverTheirCapitalsAndAccents() {
        let page = PageLines("# Café\n- [ ] Buy MILK\n- [ ] Eggs\n")
        #expect(page.lines(saying: "milk") == [2])
        #expect(page.lines(saying: "cafe") == [1])
        #expect(page.lines(saying: "bread").isEmpty)
    }

    @Test func linesGoInRemoveAndAreReplaced() throws {
        var page = PageLines("One\nTwo\nThree\n")
        page.insert(["Zero"], at: 0)
        page.insert(["Four"], at: page.count)
        #expect(page.lines == ["Zero", "One", "Two", "Three", "Four"])
        page.replace(LineRange(2, 3), with: ["1 and 2"])
        #expect(page.lines == ["Zero", "1 and 2", "Three", "Four"])
        #expect(page.remove(LineRange(1)) == ["Zero"])
        #expect(page.lines == ["1 and 2", "Three", "Four"])
        #expect(throws: CommandError.self) { try page.check(LineRange(3, 4), page: "red") }
        #expect(throws: CommandError.self) { try page.check(LineRange(0), page: "red") }
        #expect(throws: CommandError.self) { try page.check(LineRange(3, 2), page: "red") }
    }

    @Test func linesMoveUpAndDown() throws {
        var page = PageLines(lines: ["A", "B", "C", "D", "E"])
        try page.move(LineRange(4, 5), to: 1, page: "red")
        #expect(page.lines == ["A", "D", "E", "B", "C"])
        try page.move(LineRange(1), to: 5, page: "red")
        #expect(page.lines == ["D", "E", "B", "C", "A"])
        // Where they are already, nothing changes; among themselves, they can't go.
        try page.move(LineRange(2, 3), to: 1, page: "red")
        #expect(page.lines == ["D", "E", "B", "C", "A"])
        #expect(throws: CommandError.self) { try page.move(LineRange(2, 4), to: 2, page: "red") }
    }

    @Test func toDosAreTickedByTheirBoxes() throws {
        var page = PageLines("- [ ] Milk\n    - [x] Eggs\n1. [ ] Bread\nJust text\n")
        #expect(page.toDo(at: 1)?.done == false)
        #expect(page.toDo(at: 2)?.text == "Eggs")
        #expect(page.toDo(at: 4) == nil)
        #expect(try page.setToDo(at: 1, done: true, page: "red"))
        #expect(page.lines[0] == "- [x] Milk")
        #expect(try page.setToDo(at: 2, done: false, page: "red"))
        #expect(page.lines[1] == "    - [ ] Eggs")
        #expect(try page.setToDo(at: 3, done: false, page: "red") == false)
        #expect(throws: CommandError.self) { try page.setToDo(at: 4, done: true, page: "red") }
    }

    @Test func aToDoIsFoundByWhatItSays() throws {
        let page = PageLines("- [ ] Milk\n- [ ] Oat milk\n- [ ] Eggs\n- [ ] Egg cups\n")
        // Just what it says, before some more besides.
        #expect(try page.toDo(saying: "milk", page: "red") == 1)
        #expect(try page.toDo(saying: "cups", page: "red") == 4)
        #expect(throws: CommandError.self) { try page.toDo(saying: "egg", page: "red") }
        #expect(throws: CommandError.self) { try page.toDo(saying: "bread", page: "red") }
    }

    @Test func textIsReplacedOnceUnlessAll() throws {
        var page = PageLines("Tea at four\nTea at five\n")
        #expect(throws: CommandError.self) { try page.replaceText("Tea", with: "Coffee", all: false, page: "red") }
        #expect(throws: CommandError.self) { try page.replaceText("Cake", with: "Pie", all: false, page: "red") }
        #expect(try page.replaceText("four", with: "4", all: false, page: "red") == 1)
        #expect(try page.replaceText("Tea", with: "Coffee", all: true, page: "red") == 2)
        #expect(page.lines == ["Coffee at 4", "Coffee at five"])
        // Across lines, too.
        #expect(try page.replaceText("4\nCoffee", with: "4 and", all: false, page: "red") == 1)
        #expect(page.lines == ["Coffee at 4 and at five"])
    }

    @Test func linesAndPlacesAreReadAsWritten() throws {
        #expect(try LineRange(parsing: "3") == LineRange(3))
        #expect(try LineRange(parsing: "3-5") == LineRange(3, 5))
        #expect(try LineRange(parsing: "3..5") == LineRange(3, 5))
        #expect(throws: CommandError.self) { try LineRange(parsing: "three") }
        #expect(try LinePosition.after(2).position(on: 4, page: "red") == 2)
        #expect(try LinePosition.before(1).position(on: 4, page: "red") == 0)
        #expect(try LinePosition.end.position(on: 4, page: "red") == 4)
        #expect(throws: CommandError.self) { try LinePosition.after(5).position(on: 4, page: "red") }
    }
}
