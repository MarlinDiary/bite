import Foundation
import Testing
@testable import BiteKit

/// Pages as Bite's share extension left them, on the shelf for Bite to take in, and the lines it
/// moves from page to page.
struct PageShareTests {
    private func shelf() -> PageShelf {
        PageShelf(folder: FileManager.default.temporaryDirectory.appending(path: "PageShareTests-\(UUID().uuidString)"))
    }

    @Test func sharesAreTakenOnceOldestFirst() throws {
        let shelf = shelf()
        #expect(shelf.takeShares().isEmpty)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try shelf.leave(PageShare(page: 2, before: "a\n", after: "a\nsecond\n"), at: start.addingTimeInterval(1))
        try shelf.leave(PageShare(page: 0, before: "", after: "first\n"), at: start)
        #expect(shelf.takeShares().map(\.page) == [0, 2])
        #expect(shelf.takeShares().isEmpty)
    }

    @Test func theLastPageIsKept() throws {
        let shelf = shelf()
        #expect(shelf.readLastPage() == nil)
        try shelf.writeLastPage(3)
        #expect(shelf.readLastPage() == 3)
        try shelf.writeLastPage(0)
        #expect(shelf.readLastPage() == 0)
    }

    /// Onto the page as it is now: as the extension left it if it hasn't changed since, and with
    /// what changed since kept if it has.
    @Test func itGoesOnThePageAsItIsNow() {
        let share = PageShare(page: 1, before: "Ideas\nOne\n", after: "Ideas\nOne\n[A site](https://example.com)\n")
        #expect(share.applied(to: "Ideas\nOne\n") == share.after)
        #expect(share.applied(to: "Ideas changed\nOne\n") == "Ideas changed\nOne\n[A site](https://example.com)\n")
    }

    private func lines(_ texts: String...) -> [[InlineRun]] {
        texts.map { [InlineRun($0)] }
    }

    /// A web page's line links there, in the kind of line the page ends with.
    @Test func linesInTheirStylesGoOnAsIfTyped() {
        let link = [[InlineRun("A site", link: "https://example.com")]]
        #expect(PageAddition.markdown("Reading\n", adding: link, asToDo: false) == "Reading\n[A site](https://example.com)\n")
        #expect(PageAddition.markdown("- one\n", adding: link, asToDo: false) == "- one\n- [A site](https://example.com)\n")
        let styled = [[InlineRun("bold", style: .bold), InlineRun(" and plain")]]
        #expect(PageAddition.markdown("", adding: styled, asToDo: false) == "**bold** and plain\n")
        #expect(PageAddition.markdown("Same\n", adding: lines("", "  "), asToDo: false) == "Same\n")
    }

    private func split(_ now: String, own: String, lines: [[InlineRun]]) -> (own: String, lines: [[InlineRun]]) {
        PageAddition.split(now, own: own, lines: lines)
    }

    /// A to-do ticked on the page stays the page's; the lines added stay as they are.
    @Test func aChangeToThePagesOwnLinesIsThePages() {
        let own = "# Shopping\n- [ ] eggs\n- [ ] milk\n"
        let shared = lines("bread")
        let shown = PageAddition.markdown(own, adding: shared, asToDo: false)
        #expect(shown == "# Shopping\n- [ ] eggs\n- [ ] milk\n- [ ] bread\n")
        let ticked = split("# Shopping\n- [x] eggs\n- [ ] milk\n- [ ] bread\n", own: own, lines: shared)
        #expect(ticked.own == "# Shopping\n- [x] eggs\n- [ ] milk\n")
        #expect(ticked.lines == shared)
        // A line put above them, after the page's own.
        let more = split("# Shopping\n- [ ] eggs\n- [ ] milk\n- [ ] cheese\n- [ ] bread\n", own: own, lines: shared)
        #expect(more.own == "# Shopping\n- [ ] eggs\n- [ ] milk\n- [ ] cheese\n")
        #expect(more.lines == shared)
    }

    /// Typing in the lines added changes them, for every page; the page's own stay.
    @Test func aChangeToTheLinesAddedGoesWithThem() {
        let own = "Notes\n"
        let shared = [[InlineRun("A site", link: "https://example.com")]]
        let typed = split("Notes\n[A site](https://example.com) to read\n", own: own, lines: shared)
        #expect(typed.own == own)
        #expect(typed.lines == [[InlineRun("A site", link: "https://example.com"), InlineRun(" to read")]])
        let another = split("Notes\n[A site](https://example.com)\nand another\n", own: own, lines: shared)
        #expect(another.lines == [[InlineRun("A site", link: "https://example.com")], [InlineRun("and another")]])
        // All taken away.
        #expect(split("Notes\n", own: own, lines: shared) == (own, []))
    }

    /// Into an empty last line: a change above keeps the empty line the page's, under them.
    @Test func anEmptyLastLineTheyFilledStaysThePages() {
        let own = "- [ ] eggs\n- [ ]\n"
        let shared = lines("milk")
        #expect(PageAddition.markdown(own, adding: shared, asToDo: false) == "- [ ] eggs\n- [ ] milk\n")
        let ticked = split("- [x] eggs\n- [ ] milk\n", own: own, lines: shared)
        #expect(ticked.own == "- [x] eggs\n- [ ]\n")
        #expect(ticked.lines == shared)
    }

    /// Both changed at once, each kept with its own; joined into the line above, they're the
    /// page's.
    @Test func changesToBothAreEachKept() {
        let own = "One\nTwo\n"
        let shared = lines("Shared")
        let both = split("One!\nTwo\nShared, changed\n", own: own, lines: shared)
        #expect(both.own == "One!\nTwo\n")
        #expect(both.lines == lines("Shared, changed"))
        let joined = split("One\nTwoShared\n", own: own, lines: shared)
        #expect(joined.own == "One\nTwoShared\n")
        #expect(joined.lines.isEmpty)
        // With nothing added, any change is the page's.
        #expect(split("One\nTwo\nThree\n", own: own, lines: []) == ("One\nTwo\nThree\n", []))
    }

    /// The page's own lines, which what's added goes after: an empty last line is the added's.
    @Test func thePagesOwnLinesAreCounted() {
        #expect(PageAddition.keptLineCount(of: "") == 0)
        #expect(PageAddition.keptLineCount(of: "One\nTwo\n") == 2)
        #expect(PageAddition.keptLineCount(of: "Notes\n\n") == 1)
        #expect(PageAddition.keptLineCount(of: "- [ ] eggs\n- [ ]\n") == 1)
        #expect(PageAddition.keptLineCount(of: "# Title\n") == 1)
    }

    /// The lines added to a page, as they are now, for another page: their kind is the page's.
    @Test func theLinesAddedAreFoundAgain() {
        let before = "- one\n"
        let after = PageAddition.markdown(before, adding: lines("two", "three"), asToDo: false)
        #expect(PageAddition.linesAdded(to: before, making: after) == lines("two", "three"))
        // Changed in the meantime, a line after another.
        #expect(PageAddition.linesAdded(to: before, making: "- one\n- two, changed\n") == lines("two, changed"))
        // Into an empty last line.
        #expect(PageAddition.linesAdded(to: "Notes\n\n", making: "Notes\nmore\n") == lines("more"))
        #expect(PageAddition.linesAdded(to: "", making: "first\n") == lines("first"))
        // All taken away again.
        #expect(PageAddition.linesAdded(to: before, making: before) == [])
        // A line above them changed: they're not just added.
        #expect(PageAddition.linesAdded(to: before, making: "- one!\n- two\n") == nil)
        // With their links.
        let link = [[InlineRun("A site", link: "https://example.com")]]
        #expect(PageAddition.linesAdded(to: "Notes\n", making: PageAddition.markdown("Notes\n", adding: link, asToDo: false)) == link)
    }
}
