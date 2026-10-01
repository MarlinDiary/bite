import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import Bite

/// What the "…" menu does to a page.
@MainActor
struct MenuActionTests {
    private let page = "# Title\n- [x] done\n1. one\n   - nested **bold**\n> quote"

    /// Clear Text asks for no confirmation, so it has to be one undo away.
    @Test func clearingIsOneUndoAway() {
        let editor = EditorHarness(page)
        let before = editor.markdown
        let styled = NSAttributedString(attributedString: editor.textView.attributedText)
        editor.controller.clear()
        #expect(editor.markdown == "")
        #expect(editor.textView.text == "\n")
        editor.undo()
        #expect(editor.markdown == before)
        #expect(editor.textView.attributedText.isEqual(to: styled))
    }

    /// With the keyboard down, as the menu is often used, the page can still be brought back
    /// once it's being edited again.
    @Test func clearedWithTheKeyboardDownItStillComesBack() {
        let editor = EditorHarness(page)
        let before = editor.markdown
        editor.endEditing()
        editor.controller.clear()
        #expect(editor.markdown == "")
        editor.controller.focus()
        editor.undo()
        #expect(editor.markdown == before)
    }

    @Test func clearingReportsTheEmptyPageAtOnce() {
        let editor = EditorHarness(page)
        var reported: String?
        var isEmpty: Bool?
        editor.controller.onChange = { reported = $0 }
        editor.controller.onEmptyChange = { isEmpty = $0 }
        editor.controller.clear()
        #expect(reported.map(DotStore.isBlank) == true)
        #expect(isEmpty == true)
    }
}
