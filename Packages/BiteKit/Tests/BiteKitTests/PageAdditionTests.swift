import Testing
@testable import BiteKit

/// Text added to a page from Siri or Shortcuts: as if typed at the end of the page.
struct PageAdditionTests {
    private func adding(_ text: String, to markdown: String, asToDo: Bool = false) -> String {
        PageAddition.markdown(markdown, adding: text, asToDo: asToDo)
    }

    @Test func anEmptyPageTakesTheLine() {
        #expect(adding("milk", to: "") == "milk\n")
        #expect(adding("milk", to: "", asToDo: true) == "- [ ] milk\n")
    }

    @Test func itGoesOnANewLineAfterWhatsWritten() {
        #expect(adding("milk", to: "Notes\n") == "Notes\nmilk\n")
        #expect(adding("milk", to: "# Shopping\n") == "# Shopping\nmilk\n")
        #expect(adding("milk", to: "> quoted\n") == "> quoted\nmilk\n")
        #expect(adding("milk", to: "```\nlet x = 1\n```\n") == "```\nlet x = 1\n```\nmilk\n")
        #expect(adding("milk", to: "Above\n\n---\n") == "Above\n\n---\nmilk\n")
    }

    /// As Return does at the end of a list: the next item, at the same level, unticked, numbered on.
    @Test func aListThePageEndsWithCarriesOn() {
        #expect(adding("milk", to: "- [ ] eggs\n") == "- [ ] eggs\n- [ ] milk\n")
        #expect(adding("milk", to: "- [x] eggs\n") == "- [x] eggs\n- [ ] milk\n")
        #expect(adding("c", to: "- a\n    - b\n") == "- a\n    - b\n    - c\n")
        #expect(adding("c", to: "1. a\n2. b\n") == "1. a\n2. b\n3. c\n")
        #expect(adding("d", to: "a. x\nb. y\nc. z\n") == "a. x\nb. y\nc. z\nd. d\n")
    }

    /// An empty line at the end, where the caret goes, takes the text as it is.
    @Test func anEmptyLastLineTakesIt() {
        #expect(adding("milk", to: "Notes\n\n") == "Notes\nmilk\n")
        #expect(adding("milk", to: "- [ ] eggs\n- [ ]\n") == "- [ ] eggs\n- [ ] milk\n")
        #expect(adding("x", to: "3. a\n") == "3. a\n4. x\n")
        #expect(adding("x", to: "Start\n\n3.\n") == "Start\n\n3. x\n")
    }

    @Test func aToDoGoesWhereverItsAskedFor() {
        #expect(adding("milk", to: "Notes\n", asToDo: true) == "Notes\n- [ ] milk\n")
        #expect(adding("milk", to: "- a\n    - b\n", asToDo: true) == "- a\n    - b\n    - [ ] milk\n")
        #expect(adding("milk", to: "Notes\n\n", asToDo: true) == "Notes\n- [ ] milk\n")
    }

    /// Each line of the text is a line of the page; empty ones and spaces around are left out.
    @Test func severalLinesAreSeveralLines() {
        #expect(adding("eggs\n\n  milk  \r\nbread", to: "- [ ] tea\n") == "- [ ] tea\n- [ ] eggs\n- [ ] milk\n- [ ] bread\n")
        #expect(adding("a\nb", to: "") == "a\nb\n")
    }

    /// Markdown in the text stays text, as typed it would.
    @Test func markdownInItIsKeptAsText() {
        let added = adding("# not a heading *or bold*", to: "")
        #expect(MarkdownParser.parse(added).blocks == [Block(.paragraph, "# not a heading *or bold*")])
        let item = adding("[ ] not a box", to: "- a\n")
        #expect(MarkdownParser.parse(item).blocks.last == Block(.bullet, "[ ] not a box"))
    }

    @Test func nothingToAddLeavesThePage() {
        #expect(adding("", to: "Notes\n") == "Notes\n")
        #expect(adding("  \n \n", to: "Notes\n") == "Notes\n")
        #expect(adding("", to: "") == "")
    }
}
