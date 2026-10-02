import Testing
import UIKit
import BiteKit
@testable import Bite

/// The marks beside lines, bullets, numbers, checkboxes, quote bars and dividers, are drawn by
/// the text view, each in a layer of its own, where the lines themselves drew them. Writing
/// Tools takes a line's own view away while it rewrites the line, and a to-do lost its checkbox
/// for as long.
@MainActor
struct LineMarkTests {
    private func checkboxes(in editor: EditorHarness) throws -> [CGRect] {
        let layoutManager = try #require(editor.textView.textLayoutManager)
        let inset = editor.textView.textContainerInset
        var frames: [CGRect] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
            if let line = fragment as? BlockLayoutFragment, line.block.kind == .todo {
                frames.append(line.checkboxFrame.offsetBy(dx: inset.left, dy: inset.top))
            }
            return true
        }
        return frames
    }

    /// How opaque the marks are at `point` of the view, from 0 to 1.
    private func ink(at point: CGPoint, in editor: EditorHarness) throws -> CGFloat {
        let rect = CGRect(x: point.x - 0.5, y: point.y - 0.5, width: 1, height: 1)
        let image = try #require(editor.textView.lineMarksImageForTesting(of: rect).cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(pixel[3]) / 255
    }

    @Test func eachMarkedLineHasAMarkOfItsOwn() {
        let editor = EditorHarness("Title\n- a\n1. b\n- [ ] c\n> d\n---\nplain")
        editor.textView.layoutIfNeeded()
        #expect(editor.textView.lineMarkFramesForTesting.count == 5)
    }

    /// The mark is drawn where the line drew it: an open checkbox is a ring, a checked one is
    /// filled, and the mark changes as soon as the to-do does.
    @Test func aCheckboxIsDrawnInItsLayer() throws {
        let editor = EditorHarness("- [ ] open\n- [x] done")
        editor.textView.layoutIfNeeded()
        let boxes = try checkboxes(in: editor)
        try #require(boxes.count == 2)
        let marks = editor.textView.lineMarkFramesForTesting
        #expect(marks.count == 2)
        #expect(marks.indices.allSatisfy { marks[$0].contains(boxes[$0]) })
        // An open box is a ring, empty in the middle; a checked one is filled.
        let open = boxes[0], done = boxes[1]
        #expect(try ink(at: CGPoint(x: open.midX, y: open.midY), in: editor) < 0.05)
        #expect(try ink(at: CGPoint(x: open.minX + 1.2, y: open.midY), in: editor) > 0.5)
        #expect(try ink(at: CGPoint(x: done.minX + 3, y: done.minY + 3), in: editor) > 0.9)

        editor.controller.toggleTodo(at: 0)
        editor.textView.layoutIfNeeded()
        let toggled = try checkboxes(in: editor)[0]
        #expect(try ink(at: CGPoint(x: toggled.minX + 3, y: toggled.minY + 3), in: editor) > 0.9)
    }

    /// A mark changes on the spot. Scrolling passes a layer on from a line going off screen to
    /// one coming on, and it faded from the old line's mark to the new one's: a checkbox showed
    /// ring and fill at once.
    @Test func aMarkNeverFades() {
        let editor = EditorHarness("- [ ] open\n- [x] done")
        editor.textView.layoutIfNeeded()
        let layers = editor.textView.lineMarkLayersForTesting
        #expect(!layers.isEmpty)
        for key in ["contents", "position", "bounds", "hidden", "opacity"] {
            #expect(layers.allSatisfy { $0.action(forKey: key) == nil }, "\(key)")
        }
    }

    /// Lines put in above a mark's line move the mark down with it.
    @Test func aMarkFollowsItsLine() throws {
        let editor = EditorHarness("- [ ] task")
        editor.textView.layoutIfNeeded()
        let before = try #require(editor.textView.lineMarkFramesForTesting.first)
        editor.moveCaret(line: 0)
        editor.type("first\n")
        editor.textView.layoutIfNeeded()
        let box = try #require(try checkboxes(in: editor).last)
        let after = try #require(editor.textView.lineMarkFramesForTesting.last)
        #expect(after.minY > before.minY)
        #expect(after.contains(box))
    }
}
