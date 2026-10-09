import Foundation
import Testing
@testable import BiteKit

/// Which pages the watch's Smart Stack is told to show first: those changed lately.
struct PageRelevanceTests {
    private let now = Date(timeIntervalSinceReferenceDate: 813_000_000)

    private func ago(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    @Test func aPageChangedLatelyStaysToTheForeForThreeHours() {
        let pages = ["# Groceries\n- [ ] Oat milk\n", "", "# Plans\n", "# Notes\n"]
        let recent = PageRelevance.recentPages(pages, modified: [ago(60), ago(10), ago(4 * 60), nil], now: now)
        #expect(recent.map(\.page) == [0])
        #expect(recent.first?.interval == DateInterval(start: ago(60), end: ago(60).addingTimeInterval(3 * 60 * 60)))
    }

    /// One emptied lately has nothing to show.
    @Test func anEmptyPageIsntShownFirst() {
        #expect(PageRelevance.recentPages(["", "\n\n"], modified: [ago(1), ago(1)], now: now).isEmpty)
    }

    @Test func theToDosFollowTheLatestChangeToAPageWithToDosLeft() {
        let pages = ["- [ ] Milk\n", "- [ ] Bread\n", "- [x] Eggs\n", "Words\n"]
        let interval = PageRelevance.toDosInterval(pages, modified: [ago(100), ago(30), ago(5), ago(1)], now: now)
        #expect(interval == DateInterval(start: ago(30), end: ago(30).addingTimeInterval(3 * 60 * 60)))
    }

    @Test func noToDosLeftOrNoneChangedLatelyIsntShownFirst() {
        #expect(PageRelevance.toDosInterval(["- [x] Eggs\n", "Words\n"], modified: [ago(1), ago(1)], now: now) == nil)
        #expect(PageRelevance.toDosInterval(["- [ ] Milk\n"], modified: [ago(3 * 60 + 1)], now: now) == nil)
        #expect(PageRelevance.toDosInterval(["- [ ] Milk\n"], modified: [nil], now: now) == nil)
    }
}
