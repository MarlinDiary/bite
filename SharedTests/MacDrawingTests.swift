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

    /// Past the widest, the column stays exactly as wide as a panel is widened, only moving, so
    /// nothing is laid out again. Following the view, it changed by a point at every other step
    /// as the margins were rounded, and the page was laid out again each time.
    @Test func aWidePanelOnlyMovesTheColumn() {
        let editor = EditorHarness("Some text")
        let textView = editor.textView
        for width in stride(from: CGFloat(1200), through: 1210, by: 1) {
            textView.setFrameSize(NSSize(width: width, height: 400))
            #expect(textView.textContainer?.size.width == BiteTextView.widestText)
            #expect(textView.textContainerInset.width == ((width - BiteTextView.widestText) / 2).rounded(.down))
        }
    }

    /// Made wider or narrower a step at a time, as by the panel's corner, a page scrolled down
    /// keeps the line at its top where it was. Laid out again for the new width, TextKit guessed
    /// at the height of the lines not laid out yet, and the page jumped to other text, though not
    /// a line changed.
    @Test func aPageKeepsItsPlaceAsThePanelIsResized() throws {
        let editor = longPage()
        let textView = editor.textView
        let scrollView = try #require(textView.enclosingScrollView)
        textView.layoutSubtreeIfNeeded()
        try scroll(editor, to: 2400)
        let (line, offset) = try #require(lineAtTop(textView))
        #expect(line > 1000)
        var frame = scrollView.frame
        for step in 0..<12 {
            frame.size.width += step < 6 ? 3 : -3
            scrollView.frame = frame
            textView.layoutSubtreeIfNeeded()
            #expect(try abs(#require(self.offset(of: line, in: textView)) - offset) < 0.5, "step \(step)")
        }
        // Another dot's page, hidden, keeps it until it's shown.
        scrollView.isHidden = true
        for _ in 0..<4 {
            frame.size.width += 3
            scrollView.frame = frame
            textView.layoutSubtreeIfNeeded()
        }
        scrollView.isHidden = false
        textView.layoutSubtreeIfNeeded()
        #expect(try abs(#require(self.offset(of: line, in: textView)) - offset) < 0.5)
    }

    /// Dragging the panel's edge, a page keeps the line at its top where it was, under a bar as the
    /// panel's, as each step is drawn and once the edge is let go, its lines wrapping again. Laid
    /// out again at each step, TextKit guessed at the height of the lines not laid out yet, and
    /// AppKit, keeping what showed in place by those guesses, scrolled the page on by a line or
    /// more each time; lines laid out after AppKit had placed what showed were drawn where they'd
    /// been. As the live resize ended, AppKit scrolled the line to the very top, whole: a line
    /// partly scrolled away under the bar came back, and the page jumped.
    @Test(arguments: [(40, 95.0), (300, 2400.0)])
    func aPageStaysPutAsThePanelsEdgeIsDragged(lines: Int, scrolled: CGFloat) throws {
        let editor = EditorHarness((0..<lines).map { "Line \($0), long enough to take up some of the page's width" }.joined(separator: "\n"))
        let textView = editor.textView
        let scrollView = try #require(textView.enclosingScrollView)
        // In a window of its own, out of sight, resized as in a live resize.
        editor.window.contentView = NSView()
        let window = LiveResizeWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 494),
                                      styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 44, left: 0, bottom: 14, right: 0)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        textView.layoutSubtreeIfNeeded()
        try scroll(editor, to: scrolled - 44)
        let (line, offset) = try #require(lineAtTop(textView))
        var steps = 0
        window.resizeLive(by: 80, in: 24) {
            steps += 1
            #expect(abs((self.offset(of: line, in: textView) ?? .infinity) - offset) < 0.5, "step \(steps)")
            #expect(self.drawnWhereLaidOut(textView), "step \(steps)")
        }
        #expect(steps == 24)
        #expect(try abs(#require(self.offset(of: line, in: textView)) - offset) < 0.5)
        #expect(self.drawnWhereLaidOut(textView))
    }

    /// A window resized as in a live resize, as when the panel's edge is dragged: its views hear
    /// that one starts and that it ends, as AppKit tells them, with the frame changed step by step
    /// between. AppKit's own, for an animated frame change, steps by the clock, and tests running
    /// meanwhile took its time, leaving no steps. Its views don't say they're in a live resize,
    /// which only AppKit can set.
    private final class LiveResizeWindow: NSWindow {
        /// Makes it `delta` wider in `steps` steps, each laid out and drawn before `step`.
        func resizeLive(by delta: CGFloat, in steps: Int, step: () -> Void) {
            forEachView { $0.viewWillStartLiveResize() }
            let start = frame
            for index in 1...steps {
                var frame = start
                frame.size.width += delta * CGFloat(index) / CGFloat(steps)
                setFrame(frame, display: true)
                displayIfNeeded()
                step()
            }
            forEachView { $0.viewDidEndLiveResize() }
            contentView?.layoutSubtreeIfNeeded()
            displayIfNeeded()
        }

        private func forEachView(_ body: (NSView) -> Void) {
            func visit(_ view: NSView) {
                body(view)
                view.subviews.forEach(visit)
            }
            contentView.map(visit)
        }
    }

    /// Where the first line mostly in sight starts, as it wraps, and how far its top is from the
    /// top of what shows, below any bar.
    private func lineAtTop(_ textView: BiteTextView) -> (Int, CGFloat)? {
        guard let layoutManager = textView.textLayoutManager, let scrollView = textView.enclosingScrollView else { return nil }
        let top = scrollView.contentView.bounds.minY + scrollView.contentInsets.top - textView.textContainerOrigin.y
        guard let first = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, top))) else { return nil }
        var found: (Int, CGFloat)?
        layoutManager.enumerateTextLayoutFragments(from: first.rangeInElement.location) { fragment in
            let frame = fragment.layoutFragmentFrame
            let paragraph = layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments where frame.minY + line.typographicBounds.midY >= top {
                found = (paragraph + line.characterRange.location, frame.minY + line.typographicBounds.minY - top)
                return false
            }
            return true
        }
        return found
    }

    /// How far the top of the line `character` is on, as it wraps, is from the top of what shows.
    private func offset(of character: Int, in textView: BiteTextView) -> CGFloat? {
        guard let layoutManager = textView.textLayoutManager, let scrollView = textView.enclosingScrollView,
              let location = layoutManager.location(layoutManager.documentRange.location, offsetBy: character),
              let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let inParagraph = character - layoutManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard let line = fragment.textLineFragments.first(where: { NSMaxRange($0.characterRange) > inParagraph }) else { return nil }
        let top = scrollView.contentView.bounds.minY + scrollView.contentInsets.top
        return fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textView.textContainerOrigin.y - top
    }

    /// Whether each paragraph showing is drawn where it's laid out. AppKit draws each in a view of
    /// its own, in a content view, both private: a line laid out after AppKit placed those views
    /// moved in TextKit's reckoning but not on screen, which TextKit alone never shows.
    private func drawnWhereLaidOut(_ textView: BiteTextView) -> Bool {
        guard let layoutManager = textView.textLayoutManager, let range = layoutManager.textViewportLayoutController.viewportRange,
              let content = textView.subviews.first(where: { "\(type(of: $0))" == "_NSTextContentView" }) else { return false }
        var tops: [CGFloat] = []
        layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
            guard fragment.rangeInElement.location.compare(range.endLocation) == .orderedAscending else { return false }
            tops.append(fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y)
            return true
        }
        let drawn = content.subviews.map(\.frame.minY).sorted()
        return !drawn.isEmpty && zip(drawn, tops).allSatisfy { abs($0 - $1) <= 1 }
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
