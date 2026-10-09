import Testing
@testable import BiteKit

/// The pages Bite opens with the first time, on every device alike.
struct FirstLaunchPagesTests {
    @Test func thereIsAPageForEveryDotTheFirstFourWrittenOn() {
        #expect(FirstLaunchPages.markdown.count == DotPalette.count)
        #expect(FirstLaunchPages.markdown.map(\.isEmpty) == [false, false, false, false, true, true, true])
    }

    /// Its first line is a heading, which names the page in widgets, Spotlight and Apple Vision
    /// Pro's tabs.
    @Test func eachPageWrittenOnHasATitle() {
        let titles = FirstLaunchPages.markdown.prefix(4).map { PageGlance(markdown: $0).title }
        #expect(titles == ["Welcome to Bite", "Groceries", "This week", "Formatting"])
        for page in FirstLaunchPages.markdown.prefix(4) {
            #expect(page.hasPrefix("# "))
        }
    }

    /// A page goes to the person's other devices, so nothing on it is said for one of them alone.
    @Test func noPageSpeaksOfOneDevicesWays() {
        for page in FirstLaunchPages.markdown {
            let words = page.lowercased()
            for oneDevicesWay in ["tap", "click", "swipe", "⌘", "up top", "keyboard"] {
                #expect(!words.contains(oneDevicesWay), "\(oneDevicesWay) in \(page)")
            }
        }
    }
}
