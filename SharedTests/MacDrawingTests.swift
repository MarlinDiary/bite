#if !canImport(UIKit)
import AppKit
import Testing
@testable import Bite

/// What the Mac text view draws itself, from what TextKit has laid out: the selection's highlight
/// and the code blocks' backgrounds.
@MainActor
struct MacDrawingTests {
    /// 300 lines, with `middle` after the first 100.
    private func longPage(_ middle: [String] = []) -> EditorHarness {
        let lines = (0..<300).map { "Line \($0), long enough to take up some of the page's width" }
        return EditorHarness((lines[..<100] + middle + lines[100...]).joined(separator: "\n"))
    }

    private func scroll(_ editor: EditorHarness, to y: CGFloat) throws {
        let clipView = try #require(editor.textView.enclosingScrollView?.contentView)
        clipView.scroll(to: NSPoint(x: 0, y: y))
        editor.textView.enclosingScrollView?.reflectScrolledClipView(clipView)
        editor.textView.layoutSubtreeIfNeeded()
    }

    /// A selection made before the page is laid out is highlighted once it is.
    @Test func aSelectionIsHighlightedOnceThePageIsLaidOut() throws {
        let editor = EditorHarness("one\ntwo")
        editor.textView.selectedRange = NSRange(location: 0, length: 5)
        editor.textView.layoutSubtreeIfNeeded()
        let highlight = try #require(editor.textView.selectionHighlightForTesting)
        #expect(highlight.height > 0)
    }

    /// A selection taking in the whole page is highlighted from edge to edge of the screen,
    /// wherever the page is scrolled to.
    @Test func aLongSelectionIsHighlightedWhereverThePageIsScrolled() throws {
        let editor = longPage()
        editor.textView.layoutSubtreeIfNeeded()
        editor.textView.selectedRange = NSRange(location: 0, length: editor.storage.length - 1)
        for y in [0, 4000, 9000] as [CGFloat] {
            try scroll(editor, to: y)
            let visible = editor.textView.visibleRect
            let highlight = try #require(editor.textView.selectionHighlightForTesting)
            #expect(highlight.minY <= visible.minY + editor.textView.textContainerOrigin.y, "at \(y)")
            #expect(highlight.maxY >= visible.maxY, "at \(y)")
        }
    }

    /// Many lines not laid out yet lie at the top of the page, so a code block further down isn't
    /// drawn until it's scrolled to, and then where it is. It was drawn over the top of the page.
    @Test func aCodeBlockIsDrawnOnlyOnceItsLaidOut() throws {
        let editor = longPage(["```", "let x = 1", "```"])
        editor.textView.layoutSubtreeIfNeeded()
        #expect(editor.textView.codeBackgroundsForTesting.isEmpty)
        let code = (editor.textView.text as NSString).range(of: "let x = 1")
        editor.textView.scrollRangeToVisible(code)
        editor.textView.layoutSubtreeIfNeeded()
        let block = try #require(editor.textView.codeBackgroundsForTesting.first)
        #expect(editor.textView.visibleRect.intersects(block))
    }

    /// The pictures in Bite's menu rows are upright, as AppKit's are. Drawn into the row's
    /// top-down coordinates without saying so, they came out upside down.
    @Test func menuRowPicturesAreUpright() {
        let item = MenuRow.item("Up", symbol: "arrow.up", action: #selector(NSText.copy(_:)), target: nil, tint: .systemRed)
        guard let row = item.view, let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds) else {
            Issue.record("No row to draw")
            return
        }
        row.cacheDisplay(in: row.bounds, to: rep)
        // The picture's ink, left of the title: an arrow up has its head, and most of its ink, at
        // the top.
        let scale = CGFloat(rep.pixelsWide) / row.bounds.width
        var weighted = 0.0
        var total = 0.0
        for x in 0..<Int(30 * scale) {
            for y in 0..<rep.pixelsHigh {
                let ink = Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                weighted += Double(y) * ink
                total += ink
            }
        }
        #expect(total > 0)
        #expect(weighted / total < Double(rep.pixelsHigh) / 2)
    }
}
#endif
