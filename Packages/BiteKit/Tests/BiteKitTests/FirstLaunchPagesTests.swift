import Foundation
import Testing
@testable import BiteKit

/// The pages Bite opens with the first time, in each language it speaks, on every device alike.
struct FirstLaunchPagesTests {
    @Test func everyLanguageHasThem() {
        let languages = Bundle.module.localizations.filter { $0 != "Base" }
        #expect(Set(languages) == ["en", "zh-Hans", "zh-Hant", "ja", "ko"])
        #expect(FirstLaunchPages.everyLanguage.count == languages.count)
    }

    @Test func thereIsAPageForEveryDotTheFirstFourWrittenOn() {
        for pages in FirstLaunchPages.everyLanguage {
            #expect(pages.count == DotPalette.count)
            #expect(pages.map(\.isEmpty) == [false, false, false, false, true, true, true])
        }
    }

    /// Its first line is a heading, which names the page in widgets, Spotlight and Apple Vision
    /// Pro's tabs.
    @Test func eachPageWrittenOnHasATitle() {
        let titles = FirstLaunchPages.markdown.prefix(4).map { PageGlance(markdown: $0).title }
        #expect(titles == ["Welcome to Bite", "Groceries", "This week", "Formatting"])
        for pages in FirstLaunchPages.everyLanguage {
            for page in pages.prefix(4) {
                #expect(page.hasPrefix("# "))
            }
        }
    }

    /// A page goes to the person's other devices, so nothing on it is said for one of them alone,
    /// in any language.
    @Test func noPageSpeaksOfOneDevicesWays() {
        let oneDevicesWays = ["tap", "click", "swipe", "⌘", "up top", "keyboard", "点按", "轻点", "点击", "滑动", "轻扫",
                              "點一下", "點按", "點擊", "滑動", "タップ", "クリック", "スワイプ", "탭", "클릭", "스와이프"]
        for pages in FirstLaunchPages.everyLanguage {
            for page in pages {
                let words = page.lowercased()
                for way in oneDevicesWays {
                    #expect(!words.contains(way), "\(way) in \(page)")
                }
            }
        }
    }

    /// The same pages in each language: their to-dos, ticked and not, and their kinds of line.
    @Test func eachLanguageHasTheSamePages() {
        let english = FirstLaunchPages.everyLanguage.first { $0[0].hasPrefix("# Welcome") } ?? []
        for pages in FirstLaunchPages.everyLanguage {
            for dot in 0..<4 {
                let kinds = PageGlance(markdown: pages[dot]).lines.map(\.kind)
                #expect(kinds == PageGlance(markdown: english[dot]).lines.map(\.kind), "\(pages[dot])")
                #expect(PageGlance(markdown: pages[dot]).toDos == PageGlance(markdown: english[dot]).toDos)
            }
        }
    }
}
