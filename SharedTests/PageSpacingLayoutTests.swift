#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Testing
import BiteKit
@testable import Bite

/// The room the editor leaves between lines is the page's spacing (see `PageSpacing`), measured
/// on the laid-out page as clear space between the lines' letters, a code block's wash and a
/// divider's rule, whatever the lines are and however they came to be.
@MainActor
struct PageSpacingLayoutTests {
    static let page = """
    # Title
    First paragraph.
    Second paragraph.
    ## Section
    - one
    - two
    After the list.
    ### Sub
    - [ ] task
    - [x] done
    > quote one
    > quote two
    ```
    let a = 1
    let b = 2
    ```
    After the code.
    ---
    ## After the divider
    ### Right under it
    The end.
    """

    /// Each line's kind and the clear space above it, from the bottom of the line above.
    private func gaps(in editor: EditorHarness) throws -> [(kind: BlockKind, gap: CGFloat)] {
        let textView = editor.textView
        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        let theme = EditorTheme(accent: .systemRed)
        var boxes: [(kind: BlockKind, top: CGFloat, bottom: CGFloat)] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
            guard start < editor.storage.length else { return true }
            let attributes = editor.storage.attributes(at: start, effectiveRange: nil)
            let kind = BlockAttributes(attributes).kind
            let font = attributes[.font] as? PlatformFont ?? theme.bodyFont
            let rows = fragment.textLineFragments.filter { $0.characterRange.length > 0 }
            // As the markers are placed: an empty line's baseline measured up from its bottom.
            let baselines = rows.map { row in
                fragment.layoutFragmentFrame.minY + (BlockLayoutFragment.fontOfEmptyLine(row).map { row.typographicBounds.maxY + $0.descender }
                    ?? row.typographicBounds.minY + row.glyphOrigin.y)
            }
            guard let first = baselines.first, let last = baselines.last else { return true }
            let (ascent, descent) = Self.extent(of: font)
            switch kind {
            case .divider:
                let rule = first - theme.bodyFont.capHeight / 2
                boxes.append((kind, rule, rule))
            case .code:
                boxes.append((kind, first - ascent - theme.codePadding, last + descent + theme.codePadding))
            default:
                boxes.append((kind, first - ascent, last + descent))
            }
            return true
        }
        return boxes.indices.map { index in
            (boxes[index].kind, index == 0 ? boxes[index].top : boxes[index].top - boxes[index - 1].bottom)
        }
    }

    /// How far a row's letters reach above and below its baseline, as TextKit sets the row: in
    /// whole points on a Mac.
    private static func extent(of font: PlatformFont) -> (ascent: CGFloat, descent: CGFloat) {
        #if canImport(UIKit)
        (font.ascender, -font.descender)
        #else
        (font.ascender.rounded(), (-font.descender).rounded())
        #endif
    }

    /// What the page's spacing asks for between each line and the one above, at the editor's size.
    private func expected(for kinds: [BlockKind]) -> [CGFloat] {
        kinds.indices.map { index in
            index == 0 ? 0 : PageSpacing.gap(after: kinds[index - 1], before: kinds[index]) * EditorTheme.scale
        }
    }

    private func expectSpacing(_ editor: EditorHarness, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let measured = try gaps(in: editor)
        let wanted = expected(for: measured.map(\.kind))
        for (index, (line, gap)) in zip(measured, wanted).enumerated() {
            if index == 0 {
                // Nothing above the first line: its letters start at the top of the text.
                #expect(abs(line.gap) < 0.5, "first line: \(line.gap)", sourceLocation: sourceLocation)
                continue
            }
            // Between a code block's lines the wash is continuous, so the gap is between their text.
            if line.kind == .code, measured[index - 1].kind == .code {
                #expect(abs(line.gap + 2 * EditorTheme(accent: .systemRed).codePadding - gap) < 0.5,
                        "line \(index), \(line.kind) under \(measured[index - 1].kind)", sourceLocation: sourceLocation)
                continue
            }
            #expect(abs(line.gap - gap) < 0.5, "line \(index), \(line.kind) under \(measured[index - 1].kind): \(line.gap), not \(gap)",
                    sourceLocation: sourceLocation)
        }
    }

    @Test func everyGapIsThePagesSpacing() throws {
        let editor = EditorHarness(Self.page)
        let kinds = try gaps(in: editor).map(\.kind)
        #expect(kinds == [.heading1, .paragraph, .paragraph, .heading2, .bullet, .bullet, .paragraph, .heading3, .todo, .todo,
                          .quote, .quote, .code, .code, .paragraph, .divider, .heading2, .heading3, .paragraph])
        try expectSpacing(editor)
    }

    /// A line turned into a heading takes a heading's room above, and gives the line under it a
    /// heading's room below; undone, both go back.
    @Test func aLineTurnedIntoAHeadingRespacesItsNeighbours() throws {
        let editor = EditorHarness("one\ntwo\nthree")
        editor.moveCaret(line: 1)
        editor.controller.setLineStyle(.heading2)
        try expectSpacing(editor)
        #expect(try gaps(in: editor).map(\.gap).dropFirst().map { ($0 / EditorTheme.scale).rounded() } == [24, 12])
        editor.undo()
        try expectSpacing(editor)
        #expect(try gaps(in: editor).map(\.gap).dropFirst().map { ($0 / EditorTheme.scale).rounded() } == [12, 12])
    }

    /// Items typed into a list sit an item's room apart; the line after the list, a line's.
    @Test func aListTypedOutGroupsItsItems() throws {
        let editor = EditorHarness("")
        editor.type("Shopping\n- eggs\nmilk\n\nDone")
        #expect(editor.markdown == "Shopping\n- eggs\n- milk\nDone")
        try expectSpacing(editor)
        #expect(try gaps(in: editor).map(\.gap).dropFirst().map { ($0 / EditorTheme.scale).rounded() } == [12, 8, 12])
    }

    /// A divider typed between two lines has a part's room on either side of its rule, the caret
    /// going on to a new line under it.
    @Test func aTypedDividerSitsInTheMiddle() throws {
        let editor = EditorHarness("above\n\nbelow")
        editor.moveCaret(line: 1)
        editor.type("---")
        #expect(editor.markdown == "above\n---\n\nbelow")
        try expectSpacing(editor)
    }
}
