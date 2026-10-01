import Testing
@testable import Bite

/// Markdown typed at the start of a line turns into formatting, Notion style.
struct BlockShortcutTests {
    @Test func heading() {
        let editor = EditorHarness()
        editor.type("# Title")
        #expect(editor.markdown == "# Title")
    }

    @Test func headingLevels() {
        let editor = EditorHarness()
        editor.type("## Two\n### Three")
        #expect(editor.markdown == "## Two\n### Three")
    }

    @Test(arguments: ["- ", "* ", "+ "])
    func bullet(_ marker: String) {
        let editor = EditorHarness()
        editor.type(marker + "item")
        #expect(editor.markdown == "- item")
    }

    @Test func numberedListStartsAtTheTypedNumber() {
        let editor = EditorHarness()
        editor.type("7. first\nsecond")
        #expect(editor.markdown == "7. first\n8. second")
    }

    @Test func headingLevelsFourToSix() {
        let editor = EditorHarness()
        editor.type("#### Four\n##### Five\n###### Six")
        #expect(editor.markdown == "#### Four\n##### Five\n###### Six")
    }

    @Test(arguments: ["[] ", "[ ] "])
    func todo(_ marker: String) {
        let editor = EditorHarness()
        editor.type(marker + "task")
        #expect(editor.markdown == "- [ ] task")
    }

    @Test func checkedTodo() {
        let editor = EditorHarness()
        editor.type("[x] done")
        #expect(editor.markdown == "- [x] done")
    }

    @Test func bracketsNeedASpace() {
        let editor = EditorHarness()
        editor.type("[]task")
        #expect(editor.markdown == "[]task")
    }

    @Test func quote() {
        let editor = EditorHarness()
        editor.type("> said")
        #expect(editor.markdown == "> said")
    }

    @Test func dividerMovesOnToANewLine() {
        let editor = EditorHarness()
        editor.type("---after")
        #expect(editor.markdown == "---\nafter")
    }

    @Test func codeBlock() {
        let editor = EditorHarness()
        editor.type("```let x = 1")
        #expect(editor.markdown == "```\nlet x = 1\n```")
    }

    @Test func markersMidLineStayText() {
        let editor = EditorHarness()
        editor.type("a - b # c > d")
        #expect(editor.markdown == "a - b # c > d")
    }

    @Test func convertsAnExistingLine() {
        let editor = EditorHarness("hello")
        editor.moveCaret(line: 0, column: 0)
        editor.type("- ")
        #expect(editor.markdown == "- hello")
    }

    @Test func headingBecomesBullet() {
        let editor = EditorHarness("# Title")
        editor.moveCaret(line: 0, column: 0)
        editor.type("- ")
        #expect(editor.markdown == "- Title")
    }

    @Test func noShortcutsInsideCode() {
        let editor = EditorHarness("```\nx\n```")
        editor.type("\n- y **z**")
        #expect(editor.markdown == "```\nx\n- y **z**\n```")
    }
}

struct InlineShortcutTests {
    @Test func bold() {
        let editor = EditorHarness()
        editor.type("**bold** after")
        #expect(editor.markdown == "**bold** after")
    }

    @Test func italic() {
        let editor = EditorHarness()
        editor.type("*it* after")
        #expect(editor.markdown == "*it* after")
    }

    @Test func code() {
        let editor = EditorHarness()
        editor.type("`c` after")
        #expect(editor.markdown == "`c` after")
    }

    @Test func strikethrough() {
        let editor = EditorHarness()
        editor.type("~~gone~~ after")
        #expect(editor.markdown == "~~gone~~ after")
    }

    @Test func spacedStarsStayText() {
        let editor = EditorHarness()
        editor.type("a * b * c")
        #expect(editor.markdown == "a \\* b \\* c")
    }

    @Test func unfinishedBoldStaysText() {
        let editor = EditorHarness()
        editor.type("**bold")
        #expect(editor.markdown == "\\*\\*bold")
    }

    @Test func worksInsideAListItem() {
        let editor = EditorHarness()
        editor.type("- buy **milk** now")
        #expect(editor.markdown == "- buy **milk** now")
    }
}
