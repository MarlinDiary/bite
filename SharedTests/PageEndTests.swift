#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
@testable import Bite

/// A page brought to its end and kept there as it settles, as the share extension opens each page
/// where what's shared goes, until it's touched.
@MainActor
struct PageEndTests {
    /// More than a screen of lines, each wrapping, scrolled to the top.
    private func longPage() -> EditorHarness {
        let editor = EditorHarness((1...120).map { "Line \($0) of a long page, long enough to wrap onto another line" }.joined(separator: "\n"))
        editor.endEditing()
        scroll(editor, to: 0)
        return editor
    }

    private func layOut(_ editor: EditorHarness) {
        #if canImport(UIKit)
        editor.textView.layoutIfNeeded()
        #else
        editor.window.contentView?.layoutSubtreeIfNeeded()
        #endif
    }

    /// Scrolls `y` down from the top of the page.
    private func scroll(_ editor: EditorHarness, to y: CGFloat) {
        #if canImport(UIKit)
        editor.textView.contentOffset.y = y - editor.textView.contentInset.top
        #else
        guard let scrollView = editor.textView.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y - scrollView.contentInsets.top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #endif
        layOut(editor)
    }

    private func scrolled(_ editor: EditorHarness) -> CGFloat {
        #if canImport(UIKit)
        editor.textView.contentOffset.y
        #else
        editor.textView.enclosingScrollView?.contentView.bounds.minY ?? 0
        #endif
    }

    /// The page's height changes, as the share sheet's does as it settles.
    private func resize(_ editor: EditorHarness, by change: CGFloat) {
        #if canImport(UIKit)
        editor.textView.frame.size.height += change
        #else
        let size = editor.window.contentView?.frame.size ?? .zero
        editor.window.setContentSize(NSSize(width: size.width, height: size.height + change))
        #endif
        layOut(editor)
    }

    /// Whether the page shows its end as it should: its last line in sight, at the bottom, with
    /// only the room the page leaves under its text below it. The Mac's page was once scrolled on
    /// past its end, the last line at the top and nothing under it, which AppKit took as showing it.
    private func showsItsEnd(_ editor: EditorHarness) -> Bool {
        let textView = editor.textView
        #if canImport(UIKit)
        let lastLine = textView.caretRect(for: textView.endOfDocument).maxY
        let shownTo = textView.contentOffset.y + textView.bounds.height - textView.contentInset.bottom
        let room = textView.textContainerInset.bottom
        #else
        guard let layoutManager = textView.textLayoutManager, let scrollView = textView.enclosingScrollView else { return false }
        var lastLine: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: []) { fragment in
            lastLine = fragment.layoutFragmentFrame.maxY + textView.textContainerOrigin.y
            return true
        }
        let shownTo = scrollView.contentView.bounds.maxY - scrollView.contentInsets.bottom
        let room = textView.textContainerInset.height
        #endif
        return shownTo >= lastLine - 1 && shownTo - lastLine <= room + 30
    }

    /// Lets the page go, as a touch on it does on the phone, and a key pressed in it on a Mac.
    private func touch(_ editor: EditorHarness) throws {
        #if canImport(UIKit)
        editor.textView.touchDownForTesting()
        #else
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: editor.window.windowNumber, context: nil, characters: right,
                                                charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124))
        editor.textView.keyDown(with: key)
        #endif
    }

    /// TextKit guesses at the height of lines it hasn't laid out: the end it guessed at, scrolled
    /// to, was short of the real one once the lines there were laid out.
    @Test func aLongPageIsBroughtToItsEnd() {
        let editor = longPage()
        #expect(!editor.textView.showsEnd)
        #expect(!editor.controller.isAtEnd)
        editor.controller.showEnd()
        layOut(editor)
        #expect(showsItsEnd(editor))
        #expect(editor.textView.showsEnd)
        #expect(editor.controller.isAtEnd)
    }

    /// Smaller once it's at its end, as the share sheet comes up, the page is still at its end.
    /// Scrolled there only once, it was left short of it by as much as the sheet's top.
    @Test func itStaysAtItsEndAsItTakesItsSize() {
        let editor = longPage()
        editor.controller.showEnd()
        layOut(editor)
        resize(editor, by: -60)
        #expect(showsItsEnd(editor))
        resize(editor, by: 120)
        #expect(showsItsEnd(editor))
    }

    /// Asked for before the page has a size, it's at its end once it has one.
    @Test func aPageWithoutASizeYetComesToItsEndWhenItHasOne() {
        let editor = longPage()
        #if canImport(UIKit)
        let frame = editor.textView.frame
        editor.textView.frame.size.height = 0
        editor.controller.showEnd()
        layOut(editor)
        editor.textView.frame = frame
        #else
        let size = editor.window.contentView?.frame.size ?? .zero
        editor.window.setContentSize(NSSize(width: size.width, height: 0))
        editor.controller.showEnd()
        layOut(editor)
        editor.window.setContentSize(size)
        #endif
        layOut(editor)
        #expect(showsItsEnd(editor))
    }

    /// Touched, the page is the person's to scroll: scrolled up, it stays there as it changes size.
    @Test func aTouchLetsItGo() throws {
        let editor = longPage()
        editor.controller.showEnd()
        layOut(editor)
        try touch(editor)
        #expect(!editor.textView.keepsEnd)
        scroll(editor, to: 400)
        let place = scrolled(editor)
        resize(editor, by: -60)
        #expect(!editor.controller.isAtEnd)
        #expect(abs(scrolled(editor) - place) < 1)
    }

    /// A page shorter than the screen shows its end as it is.
    @Test func aShortPageShowsItsEnd() {
        let editor = EditorHarness("Just a line")
        layOut(editor)
        #expect(editor.textView.showsEnd)
        #expect(editor.controller.isAtEnd)
    }
}
