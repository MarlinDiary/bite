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

    /// Lines grow no longer than Notion's: a wider page only widens the margins, the text in
    /// the middle; narrower, the margins are as ever.
    @Test func linesStopGrowingAtAReadableLength() throws {
        let editor = EditorHarness("Some text")
        let textView = editor.textView
        textView.setFrameSize(NSSize(width: 1200, height: 400))
        #expect(textView.textContainerInset.width == 270)
        #expect(textView.textContainer?.size.width == BiteTextView.widestText)
        textView.setFrameSize(NSSize(width: 500, height: 400))
        #expect(textView.textContainerInset.width == BiteTextView.sideMargin)
        #expect(textView.textContainer?.size.width == 460)
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

    /// Where character `location` is drawn, in the text view.
    private func frame(of location: Int, in editor: EditorHarness) -> CGRect {
        let view = editor.textView
        let onScreen = view.firstRect(forCharacterRange: NSRange(location: location, length: 1), actualRange: nil)
        let inWindow = editor.window.convertFromScreen(onScreen)
        return view.convert(inWindow, from: nil)
    }

    /// A selection starting partway along a line lights nothing left of its start above the next
    /// line's text: the spacing between them went from the left edge, a strip under the part of
    /// the line not selected, and beside a checkbox the room above it did too.
    @Test(arguments: ["Plain first line here\nThe second line", "# Bite's List\n- [ ] Mac one\n- [ ] two"])
    func aSelectionStartingPartwayLightsNothingLeftOfItsStart(_ page: String) throws {
        let editor = EditorHarness(page)
        let view = editor.textView
        view.layoutSubtreeIfNeeded()
        let firstLine = (view.string as NSString).range(of: "\n").location
        let start = firstLine - 4
        view.setSelectedRange(NSRange(location: start, length: view.string.utf16.count - 1 - start))
        view.layoutSubtreeIfNeeded()
        let startFrame = frame(of: start, in: editor)
        // The second line's last character, "e" or "o", where its text is.
        let secondLine = NSMaxRange((view.string as NSString).paragraphRange(for: NSRange(location: firstLine + 1, length: 0))) - 2
        let secondFrame = frame(of: secondLine, in: editor)
        let gap = (startFrame.maxY + secondFrame.minY) / 2
        #expect(secondFrame.minY > startFrame.maxY)
        // Left of the start, between the lines: unlit. Right of it: lit, the shape still one.
        #expect(!view.selectionHighlightContainsForTesting(CGPoint(x: startFrame.minX - 30, y: gap)))
        #expect(view.selectionHighlightContainsForTesting(CGPoint(x: startFrame.minX + 10, y: gap)))
        // The second line itself is lit where its text is.
        #expect(view.selectionHighlightContainsForTesting(CGPoint(x: secondFrame.midX, y: secondFrame.midY)))
    }
}
#endif
