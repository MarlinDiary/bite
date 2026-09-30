import Testing
import UIKit
import BiteKit
@testable import Bite

/// Emptying a line must not move anything: not the lines around it, not its marker, not the
/// caret. TextKit lays out empty lines a little differently, and the page used to jump.
struct EmptyLineLayoutTests {
    private struct Line: Equatable {
        let top: CGFloat
        let height: CGFloat
        let caretTop: CGFloat
        let caretHeight: CGFloat
        let checkboxTop: CGFloat?
    }

    /// Where each line of the page ends up.
    private func layout(_ harness: EditorHarness) -> [Line] {
        let textView = harness.textView
        guard let layoutManager = textView.textLayoutManager else { return [] }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let string = textView.textStorage.string as NSString
        var lines: [Line] = []
        var location = 0
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let end = NSMaxRange(range) - 1
            guard let textLocation = layoutManager.location(layoutManager.documentRange.location, offsetBy: end),
                  let fragment = layoutManager.textLayoutFragment(for: textLocation),
                  let position = textView.position(from: textView.beginningOfDocument, offset: end) else { break }
            let caret = textView.caretRect(for: position)
            let checkbox = (fragment as? BlockLayoutFragment).flatMap { $0.block.kind == .todo ? $0.checkboxFrame.minY : nil }
            lines.append(Line(top: fragment.layoutFragmentFrame.minY, height: fragment.layoutFragmentFrame.height,
                              caretTop: caret.minY, caretHeight: caret.height, checkboxTop: checkbox))
            location = NSMaxRange(range)
        }
        return lines
    }

    @Test(arguments: ["- [ ] ", "1. ", "- ", "> ", ""])
    func emptyingALineMovesNothing(marker: String) {
        let markdown = "\(marker)one\n\(marker)two\n\(marker)three"
        let full = layout(EditorHarness(markdown))
        #expect(full.count == 3)
        // The middle line, then the last one, which TextKit treats differently again.
        for (line, length) in [(1, 3), (2, 5)] {
            let harness = EditorHarness(markdown)
            harness.moveCaret(line: line)
            harness.backspace(length)
            #expect(layout(harness) == full, "emptied line \(line)")
        }
    }
}
