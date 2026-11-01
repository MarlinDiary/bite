#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// Words said into a page with voice input: written at its end as they're heard, not where the
/// caret is, the last ones still being made out until the next words replace them, and tidied in
/// their place once it stops (see `EditorController.dictate`).
@MainActor
struct DictationTests {
    /// After a line with something on it the words go on a line of their own, the caret staying on
    /// the text it was on; words still being made out are replaced by the next ones heard.
    @Test func wordsGoOnALineOfTheirOwnAtTheEnd() {
        let editor = EditorHarness("First\nSecond")
        editor.moveCaret(line: 0, column: 2)
        editor.controller.beginDictation()
        editor.controller.dictate("Hello", pending: " wor")
        #expect(editor.textView.text == "First\nSecond\nHello wor\n")
        #expect(editor.caret == 2)
        editor.controller.dictate(" world.", pending: " And")
        editor.controller.dictate("", pending: " then")
        #expect(editor.markdown == "First\nSecond\nHello world. then")
        editor.controller.settleDictation()
        #expect(editor.markdown == "First\nSecond\nHello world. then")
        #expect(editor.controller.dictatedMarkdown == "Hello world. then")
        #expect(editor.caret == 2)
    }

    /// An empty line at the end takes them as typed there, a to-do staying one; but not the line
    /// being typed on, under the caret.
    @Test func anEmptyLastLineTakesThem() {
        let list = EditorHarness("- [ ] milk\n- [ ] ")
        list.endEditing()
        list.controller.beginDictation()
        list.controller.dictate("eggs", pending: "")
        #expect(list.markdown == "- [ ] milk\n- [ ] eggs")
        let typedOn = EditorHarness("a\n\n")
        typedOn.controller.beginDictation()
        typedOn.controller.dictate("b", pending: "")
        #expect(typedOn.textView.text == "a\n\nb\n")
    }

    /// The page typed in above them: they keep their place, and what's tidied is only what was
    /// said, the page before it what it's tidied to fit.
    @Test func typingAboveThemKeepsTheirPlace() {
        let editor = EditorHarness("Top")
        editor.controller.beginDictation()
        editor.controller.dictate("Said", pending: " so")
        editor.moveCaret(line: 0)
        editor.type("!")
        editor.controller.dictate(" far", pending: "")
        #expect(editor.markdown == "Top!\nSaid far")
        #expect(editor.controller.dictatedMarkdown == "Said far")
        #expect(editor.controller.markdownBeforeDictation(limit: 100) == "Top!\n")
    }

    /// Tidied, what was said gives way to the tidy text, in the page's kind of lines; undo brings
    /// back what was said, as heard.
    @Test func theTidyTextTakesItsPlaceAndUndoBringsItBack() {
        let editor = EditorHarness("# List\n- [ ] milk")
        editor.endEditing()
        editor.controller.beginDictation()
        editor.controller.dictate("um eggs and bread", pending: "")
        let said = editor.controller.dictatedMarkdown
        #expect(said == "um eggs and bread")
        editor.controller.endDictation(replacingWith: "- [ ] eggs\n- [ ] bread\n", ifStill: said)
        #expect(editor.markdown == "# List\n- [ ] milk\n- [ ] eggs\n- [ ] bread")
        #expect(!editor.controller.isDictating)
        editor.undo()
        #expect(editor.markdown == "# List\n- [ ] milk\num eggs and bread")
    }

    /// Changed since it was sent to be tidied, what was said stays as it now is.
    @Test func changedSinceItWasSentItStays() {
        let editor = EditorHarness("Note")
        editor.controller.beginDictation()
        editor.controller.dictate("first try", pending: "")
        let said = editor.controller.dictatedMarkdown
        editor.moveCaret(line: 1)
        editor.type("!")
        editor.controller.endDictation(replacingWith: "First try.", ifStill: said)
        #expect(editor.markdown == "Note\nfirst try!")
    }

    /// The words still being made out aren't the page's yet: the caret goes no further than where
    /// they start, and nothing typed or deleted goes into them.
    @Test func theCaretKeepsOffWordsStillBeingMadeOut() {
        let editor = EditorHarness("Note")
        editor.controller.beginDictation()
        editor.controller.dictate("final", pending: " maybe")
        let start = ("Note\nfinal" as NSString).length
        let inside = NSRange(location: start + 3, length: 0)
        #if canImport(UIKit)
        editor.textView.selectedRange = inside
        editor.controller.selectionChanged()
        #expect(editor.caret == start)
        #else
        #expect(editor.controller.allowedSelection(inside) == NSRange(location: start, length: 0))
        #endif
        #expect(!editor.controller.shouldChange(NSRange(location: start + 1, length: 2), to: ""))
        #expect(!editor.controller.shouldChange(NSRange(location: start + 2, length: 0), to: "x"))
        // Heard for good, they're the page's like any other.
        editor.controller.settleDictation()
        #if canImport(UIKit)
        editor.textView.selectedRange = inside
        editor.controller.selectionChanged()
        #expect(editor.caret == start + 3)
        #else
        #expect(editor.controller.allowedSelection(inside) == inside)
        #endif
    }

    /// While an input method composes, words heard wait, and go in once it's done, with the next
    /// words heard, or a moment later.
    @Test func wordsWaitWhileAnInputMethodComposes() {
        let editor = EditorHarness("Note")
        editor.controller.beginDictation()
        editor.moveCaret(line: 0)
        editor.startComposing("ni")
        editor.controller.dictate("heard", pending: "")
        #expect(!editor.textView.text.contains("heard"))
        editor.compose([], commit: "你")
        editor.controller.dictate(" too", pending: "")
        #expect(editor.textView.text == "Note你\nheard too\n")
    }

    /// The page cleared as words come: they go on at its end as it now is, starting with a word,
    /// not the space heard before an English one.
    @Test func aPageClearedTakesThemAtItsNewEnd() {
        let editor = EditorHarness("Old")
        editor.endEditing()
        editor.controller.beginDictation()
        editor.controller.dictate("one", pending: " two")
        editor.controller.load(markdown: "")
        editor.controller.dictate(" three", pending: "")
        #expect(editor.markdown == "three")
    }
}
