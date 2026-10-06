#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// A page changed on another device, taken in while it's open here.
@MainActor
struct RemoteChangeTests {
    @Test func onlyTheChangedLineIsReplacedAndTheCaretStaysOnItsText() {
        let editor = EditorHarness("first\nsecond\nthird")
        editor.moveCaret(line: 2, column: 3)
        let caret = editor.caret
        editor.controller.applyRemote(markdown: "first\nsecond, changed elsewhere\nthird")
        #expect(editor.markdown == "first\nsecond, changed elsewhere\nthird")
        #expect(editor.caret == caret + (", changed elsewhere" as NSString).length)
        #expect(EditorFuzzTests.problems(in: editor).isEmpty)
    }

    /// Where each line is laid out, from the top, the whole page laid out first.
    private func lineTops(_ editor: EditorHarness) -> [CGFloat] {
        #if canImport(UIKit)
        editor.textView.layoutIfNeeded()
        #else
        editor.textView.layoutSubtreeIfNeeded()
        #endif
        guard let manager = editor.textView.textLayoutManager else { return [] }
        manager.ensureLayout(for: manager.documentRange)
        var tops: [CGFloat] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            tops.append(fragment.layoutFragmentFrame.minY)
            return true
        }
        return tops
    }

    /// Lines added at the end go as far below the last as lines loaded so do: the line that had
    /// been last, laid out as the page's end, kept no room below it. The page to match is laid out
    /// before the other is made, which with keys up takes them from it.
    @Test func linesAddedAtTheEndAreSpacedAsIfLoaded() {
        let loaded = lineTops(EditorHarness("Shopping\n- [ ] eggs\n- [ ] milk"))
        let editor = EditorHarness("Shopping\n- [ ] eggs")
        _ = lineTops(editor)
        editor.controller.applyRemote(markdown: "Shopping\n- [ ] eggs\n- [ ] milk\n")
        #expect(lineTops(editor) == loaded)
    }

    @Test func aCaretAboveTheChangeStaysPut() {
        let editor = EditorHarness("first\nsecond\nthird")
        editor.moveCaret(line: 0, column: 2)
        editor.controller.applyRemote(markdown: "first\nsecond\nthird, and more")
        #expect(editor.caret == 2)
    }

    /// The caret in a line that changed stays in it, as far along as it fits.
    @Test func aCaretInAChangedLineStaysInIt() {
        let editor = EditorHarness("first\nsecond line\nthird")
        editor.moveCaret(line: 1, column: 9)
        editor.controller.applyRemote(markdown: "first\nnew\nthird")
        let text = editor.textView.text as NSString
        #expect(NSLocationInRange(editor.caret, NSRange(location: 6, length: 4)))
        #expect(text.substring(with: NSRange(location: 6, length: 3)) == "new")
    }

    @Test func aListIsNumberedAgain() {
        let editor = EditorHarness("1. one\n2. two\n3. three")
        editor.controller.applyRemote(markdown: "1. one\n2. inserted\n3. two\n4. three")
        #expect(editor.markdown == "1. one\n2. inserted\n3. two\n4. three")
        let last = (editor.textView.text as NSString).range(of: "three")
        #expect(editor.storage.attribute(.biteOrdinal, at: last.location, effectiveRange: nil) as? Int == 4)
        #expect(EditorFuzzTests.problems(in: editor).isEmpty)
    }

    /// What came in is already the page's: it isn't reported back to go out again.
    @Test func nothingIsReportedBack() {
        let editor = EditorHarness("a")
        var reported: [String] = []
        editor.controller.onChange = { reported.append($0) }
        editor.controller.applyRemote(markdown: "a\nb")
        editor.controller.reportPendingChange()
        #expect(reported.isEmpty)
    }

    @Test func aPageEmptiedElsewhereSaysSo() {
        let editor = EditorHarness("a")
        var empty: [Bool] = []
        editor.controller.onEmptyChange = { empty.append($0) }
        editor.controller.applyRemote(markdown: "")
        #expect(empty == [true])
        #expect(editor.markdown == "")
    }

    /// The system's undo for typing knows only where text was, and would take out whatever moved
    /// there since.
    @Test func undoStartsOver() {
        let editor = EditorHarness("a\nb")
        editor.moveCaret(line: 1)
        editor.type("x")
        editor.controller.applyRemote(markdown: "A longer first line\nbx")
        #expect(editor.textView.undoManager?.canUndo == false)
        #expect(editor.markdown == "A longer first line\nbx")
    }

    /// Random pages changed in random ways elsewhere come in as if loaded afresh, and sound.
    @Test func randomChangesComeInAsIfLoaded() {
        let kinds = ["plain", "- item", "1. numbered", "## heading", "> quote", "- [ ] task", "- [x] done", "---",
                     "```", "code", "**bold** and `code`", "", "    - nested"]
        var random = Random(seed: 11)
        for _ in 0..<150 {
            var lines = (0..<random.next(upTo: 12)).map { _ in kinds[random.next(upTo: kinds.count)] + " \(random.next(upTo: 9))" }
            let old = lines.joined(separator: "\n")
            for _ in 0..<random.next(upTo: 4) + 1 {
                let line = kinds[random.next(upTo: kinds.count)] + " \(random.next(upTo: 9))"
                switch random.next(upTo: 3) {
                case 0: lines.insert(line, at: random.next(upTo: lines.count + 1))
                case 1 where !lines.isEmpty: lines.remove(at: random.next(upTo: lines.count))
                default: if !lines.isEmpty { lines[random.next(upTo: lines.count)] = line }
                }
            }
            let new = lines.joined(separator: "\n")
            let editor = EditorHarness(old)
            editor.moveCaret(line: random.next(upTo: max(1, old.components(separatedBy: "\n").count)))
            editor.controller.applyRemote(markdown: new)
            #expect(editor.markdown == EditorHarness(new).markdown, "\(old.debugDescription) to \(new.debugDescription)")
            let problems = EditorFuzzTests.problems(in: editor)
            #expect(problems.isEmpty, "\(problems) after \(old.debugDescription) to \(new.debugDescription)")
        }
    }
}

private struct Random {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}
