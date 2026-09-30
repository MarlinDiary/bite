import Testing
import UIKit
import BiteKit
@testable import Bite

/// Which styles the format bar shows as on: they tell what typing will do, and tapping one
/// that's on undoes it.
struct FormatBarStateTests {
    @Test func boldStaysOnUntilTappedAgain() {
        let editor = EditorHarness("a")
        editor.moveCaret(line: 0)
        #expect(!FormatBar.shared.showsOn(.bold))
        editor.controller.perform(.bold)
        #expect(FormatBar.shared.showsOn(.bold))
        editor.type("b")
        #expect(FormatBar.shared.showsOn(.bold))
        editor.controller.perform(.bold)
        #expect(!FormatBar.shared.showsOn(.bold))
        editor.type("c")
        #expect(editor.markdown == "a**b**c")
    }

    @Test func caretFollowsTheTextBeforeIt() {
        let editor = EditorHarness("a **b** c")
        editor.moveCaret(line: 0, column: 3)
        #expect(editor.controller.activeStyles == .bold)
        editor.moveCaret(line: 0, column: 5)
        #expect(editor.controller.activeStyles.isEmpty)
    }

    @Test func tappingBoldAfterBoldTextTurnsItOff() {
        let editor = EditorHarness("**a**")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bold)
        editor.type("b")
        #expect(editor.markdown == "**a**b")
    }

    @Test func selectionShowsWhatAllOfItHas() {
        let editor = EditorHarness("***ab*** *c*")
        editor.select(from: (0, 0), to: (0, 2))
        #expect(editor.controller.activeStyles == [.bold, .italic])
        editor.select(from: (0, 0), to: (0, 4))
        #expect(editor.controller.activeStyles.isEmpty)
    }

    @Test func lineBreaksDontCountInASelection() {
        let editor = EditorHarness("- **ab**\n- **cd**")
        editor.select(from: (0, 1), to: (1, 1))
        #expect(editor.controller.activeStyles == .bold)
        editor.controller.perform(.bold)
        #expect(editor.markdown == "- **a**b\n- c**d**")
    }

    /// A line's kind shows on the page itself.
    @Test func lineKindsDontShowOnTheBar() {
        let editor = EditorHarness("- [ ] a")
        editor.moveCaret(line: 0)
        #expect(!FormatBar.shared.showsOn(.todo))
        editor.controller.perform(.quote)
        #expect(!FormatBar.shared.showsOn(.quote))
    }

    @Test func codeTakesNoInlineStyle() {
        let editor = EditorHarness("```\nx\n```")
        editor.moveCaret(line: 0)
        editor.controller.perform(.bold)
        #expect(editor.controller.activeStyles.isEmpty)
        editor.type("y")
        #expect(editor.markdown == "```\nxy\n```")
    }
}
