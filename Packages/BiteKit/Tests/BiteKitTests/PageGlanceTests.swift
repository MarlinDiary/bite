import Foundation
import Testing
@testable import BiteKit

/// A page as Bite's widgets show it, and how they turn to another and open Bite on it.
struct PageGlanceTests {
    @Test func linesAreThePagesWithTheirNumbers() {
        let glance = PageGlance(markdown: "# Shopping\n- [ ] eggs\n- [x] milk\n1. first\n2. second\n    1. inner\n> said\n")
        #expect(glance.lines.map(\.kind) == [.heading1, .todo, .todo, .ordered, .ordered, .ordered, .quote])
        #expect(glance.lines.map(\.isChecked) == [false, false, true, false, false, false, false])
        #expect(glance.lines.map(\.label) == [nil, nil, nil, "1.", "2.", "a.", nil])
        #expect(glance.lines[5].indent == 1)
        #expect(glance.lines[2].text == "milk")
    }

    /// Bold, links and the rest keep their runs, as the editor draws them.
    @Test func runsKeepTheirLook() {
        let line = PageGlance(markdown: "Buy **eggs** at [the shop](https://example.com)").lines[0]
        #expect(line.runs.map(\.text) == ["Buy ", "eggs", " at ", "the shop"])
        #expect(line.runs[1].style == .bold)
        #expect(line.runs[3].link == "https://example.com")
    }

    /// A widget has little room: empty lines at either end go, and empty lines in a row are one.
    @Test func emptyLinesTakeLittleRoom() {
        let glance = PageGlance(markdown: "\n\nTop\n\n\n\nBottom\n\n\n")
        #expect(glance.lines.map(\.text) == ["Top", "", "Bottom"])
        #expect(glance.lines[1].isBlank)
        #expect(PageGlance(markdown: "\n\n").isEmpty)
        #expect(PageGlance(markdown: "").isEmpty)
        #expect(!PageGlance(markdown: "---").isEmpty)
    }

    /// For the Lock Screen: what the page is about, and its to-dos still to do.
    @Test func titleAndToDos() {
        let glance = PageGlance(markdown: "\n# Groceries\n- [ ] eggs\n- [x] milk\n- [ ] bread\nnotes\n")
        #expect(glance.title == "Groceries")
        #expect(glance.toDos.open == 2)
        #expect(glance.toDos.all == 3)
        #expect(PageGlance(markdown: "---\n  \n- [ ] tea").title == "tea")
        #expect(PageGlance(markdown: "").title == nil)
        #expect(PageGlance(markdown: "Plain").toDos.all == 0)
    }

    /// The arrow goes to the next page with something on it, round from the last to the first.
    @Test func turningSkipsEmptyPages() {
        let isEmpty = [false, true, false, true, true, false, true]
        #expect(PageTurns.next(after: 0, isEmpty: isEmpty) == 2)
        #expect(PageTurns.next(after: 2, isEmpty: isEmpty) == 5)
        #expect(PageTurns.next(after: 5, isEmpty: isEmpty) == 0)
        // From an empty page it carries on to the next page with something on it.
        #expect(PageTurns.next(after: 3, isEmpty: isEmpty) == 5)
        // With nothing anywhere else, it stays.
        #expect(PageTurns.next(after: 4, isEmpty: [true, true, true, true, false, true, true]) == 4)
        #expect(PageTurns.next(after: 4, isEmpty: Array(repeating: true, count: 7)) == 4)
    }

    @Test func linksOpenTheirPage() {
        for page in 0..<DotPalette.count {
            #expect(PageTurns.page(openedBy: PageTurns.link(to: page)) == page)
        }
        #expect(PageTurns.link(to: 0).absoluteString == "com.chenyeni.bite://page/1")
        #expect(PageTurns.page(openedBy: URL(string: "com.chenyeni.bite://page/8")!) == nil)
        #expect(PageTurns.page(openedBy: URL(string: "com.chenyeni.bite://page/0")!) == nil)
        #expect(PageTurns.page(openedBy: URL(string: "com.chenyeni.bite://other/1")!) == nil)
        #expect(PageTurns.page(openedBy: URL(string: "https://page/1")!) == nil)
    }

    /// Written all at once and read back as written; nothing before Bite has written any.
    @Test func theShelfKeepsThePages() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PageShelfTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let shelf = PageShelf(folder: folder)
        #expect(shelf.read() == nil)
        let pages = ["# One\n", "", "- [ ] two\n", "", "", "", "seven"]
        try shelf.write(pages)
        #expect(shelf.read() == pages)
        try shelf.write(Array(repeating: "", count: 7))
        #expect(shelf.read() == Array(repeating: "", count: 7))
    }
}
