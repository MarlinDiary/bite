import Testing
@testable import Bite

/// Which dots the dot bar shows in their colour.
@MainActor
struct DotColorsTests {
    /// Bite's shows a page's by whether it has something on it.
    @Test func bitesDotsFollowWhatsOnThePages() {
        let isEmpty = [true, false]
        #expect(!DotColors.byContent.isColoured(0, isSelected: true, isEmpty: isEmpty))
        #expect(DotColors.byContent.isColoured(1, isSelected: false, isEmpty: isEmpty))
    }

    /// The share extension's shows each page as Add would leave it: the page on screen as it is,
    /// with what's shared, and the others by their own lines, without it.
    @Test func theSharesDotsFollowThePagesAsAddWouldLeaveThem() {
        // Every page shows what's shared at its end, so none is empty as it shows.
        let shows = [false, false, false]
        let colours = DotColors.asAdded(ownIsEmpty: [true, false, true])
        #expect(colours.isColoured(0, isSelected: true, isEmpty: shows))
        #expect(!colours.isColoured(0, isSelected: false, isEmpty: shows))
        #expect(colours.isColoured(1, isSelected: false, isEmpty: shows))
        #expect(!colours.isColoured(2, isSelected: false, isEmpty: shows))
    }

    /// What's shared taken off the page on screen, with nothing else on it: its dot is empty.
    @Test func aPageLeftWithNothingOnItHasAnEmptyDot() {
        let colours = DotColors.asAdded(ownIsEmpty: [true, false])
        #expect(!colours.isColoured(0, isSelected: true, isEmpty: [true, false]))
    }
}
