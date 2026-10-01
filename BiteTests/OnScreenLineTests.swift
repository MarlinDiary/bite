import Testing
import UIKit
import BiteKit
@testable import Bite

/// What the text view finds among the lines on screen: the code blocks it draws backgrounds
/// for, and the checkbox under a touch.
@MainActor
struct OnScreenLineTests {
    /// Many lines not laid out yet lie at the top of the page, so a code block further down isn't
    /// drawn until it's scrolled to, and then where it is. It was drawn over the first line.
    @Test func aCodeBlockIsDrawnOnlyOnceItsOnScreen() throws {
        let lines = (0..<300).map { "Line \($0), long enough to take up some of the page's width" }
        let editor = EditorHarness((lines[..<100] + ["```", "let x = 1", "```"] + lines[100...]).joined(separator: "\n"))
        let textView = editor.textView
        textView.layoutIfNeeded()
        #expect(textView.codeBackgroundsForTesting.isEmpty)
        // Scrolled to the code, which is laid out only once it's on screen, and then turns out to
        // be somewhere else than TextKit guessed.
        let layoutManager = try #require(textView.textLayoutManager)
        let code = (textView.text as NSString).range(of: "let x = 1").location
        let location = try #require(layoutManager.location(layoutManager.documentRange.location, offsetBy: code))
        for _ in 0..<4 {
            layoutManager.ensureLayout(for: NSTextRange(location: location))
            let line = try #require(layoutManager.textLayoutFragment(for: location))
            textView.contentOffset.y = line.layoutFragmentFrame.minY + textView.textContainerInset.top - 300
            textView.layoutIfNeeded()
        }
        let block = try #require(textView.codeBackgroundsForTesting.first)
        let screen = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
        #expect(screen.intersects(block))
        let line = try #require(layoutManager.textLayoutFragment(for: location)).layoutFragmentFrame
        #expect(block.contains(CGPoint(x: line.midX + textView.textContainerInset.left, y: line.midY + textView.textContainerInset.top)))
    }

    @Test func aTapOnTheCheckboxFindsItsLine() throws {
        let editor = EditorHarness("text\n- [ ] task")
        editor.textView.layoutIfNeeded()
        let layoutManager = try #require(editor.textView.textLayoutManager)
        var checkbox: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let line = fragment as? BlockLayoutFragment, line.block.kind == .todo {
                checkbox = line.checkboxFrame
                return false
            }
            return true
        }
        let frame = try #require(checkbox)
        let inset = editor.textView.textContainerInset
        let point = CGPoint(x: frame.midX + inset.left, y: frame.midY + inset.top)
        #expect(editor.textView.todoLocation(at: point) == 5)
        #expect(editor.textView.todoLocation(at: CGPoint(x: point.x + 120, y: point.y)) == nil)
        // Below the last line, where there's no line at all.
        #expect(editor.textView.todoLocation(at: CGPoint(x: point.x, y: point.y + 300)) == nil)
    }
}
