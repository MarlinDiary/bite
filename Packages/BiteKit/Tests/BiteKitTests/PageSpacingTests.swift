import Foundation
import Testing
@testable import BiteKit

/// The room between a page's lines: closer the more two lines belong together.
struct PageSpacingTests {
    private func gap(_ previous: BlockKind, _ kind: BlockKind) -> CGFloat {
        PageSpacing.gap(after: previous, before: kind)
    }

    /// Items of one list and lines of one quote sit closer than separate lines, and further apart
    /// than the rows of a line that wraps.
    @Test func groupsSitCloserThanLines() {
        #expect(gap(.paragraph, .paragraph) == 12)
        for previous in [BlockKind.bullet, .ordered, .todo] {
            for kind in [BlockKind.bullet, .ordered, .todo] {
                #expect(gap(previous, kind) == 8)
            }
        }
        #expect(gap(.quote, .quote) == 8)
        #expect(PageSpacing.rowGap(.paragraph) == 4)
        #expect(PageSpacing.rowGap(.todo) == 4)
        // A list or a quote is parted from the lines round it as any line is.
        #expect(gap(.paragraph, .bullet) == 12)
        #expect(gap(.todo, .paragraph) == 12)
        #expect(gap(.quote, .bullet) == 12)
        #expect(gap(.paragraph, .quote) == 12)
    }

    /// A heading is twice as far from what's above it as from what's below; the page's title a
    /// step more on both sides.
    @Test func aHeadingBelongsToWhatFollowsIt() {
        for heading in [BlockKind.heading2, .heading3, .heading4, .heading5, .heading6] {
            for kind in [BlockKind.paragraph, .bullet, .todo, .quote, .code] {
                #expect(gap(kind, heading) == 24)
                #expect(gap(heading, kind) == 12)
            }
        }
        #expect(gap(.paragraph, .heading1) == 32)
        #expect(gap(.heading1, .paragraph) == 16)
        #expect(PageSpacing.rowGap(.heading2) == 2)
    }

    /// Two headings in a row stay together, and a divider has already parted what follows it.
    @Test func headingsInARowStayTogether() {
        #expect(gap(.heading1, .heading2) == 16)
        #expect(gap(.heading2, .heading3) == 12)
        #expect(gap(.divider, .heading1) == 24)
        #expect(gap(.divider, .heading2) == 24)
    }

    /// A divider has a part's room on either side; a code block's lines are its rows.
    @Test func dividersPartAndCodeHangsTogether() {
        #expect(gap(.paragraph, .divider) == 24)
        #expect(gap(.divider, .paragraph) == 24)
        #expect(gap(.todo, .divider) == 24)
        #expect(gap(.code, .code) == 2)
        #expect(gap(.paragraph, .code) == 12)
        #expect(gap(.code, .paragraph) == 12)
    }

    /// Every gap is a step of four points, but the closer rows of headings and code.
    @Test func gapsGoUpInSteps() {
        for previous in BlockKind.allCases {
            for kind in BlockKind.allCases where !(previous == .code && kind == .code) {
                #expect(gap(previous, kind).truncatingRemainder(dividingBy: 4) == 0)
            }
        }
    }
}
