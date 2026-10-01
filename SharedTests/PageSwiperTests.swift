#if !canImport(UIKit)
import Foundation
import Testing
@testable import Bite

/// Two fingers sliding sideways on a trackpad, as the phone's pager takes a finger.
@MainActor
struct PageSwiperTests {
    private func swiper(on page: Int) -> PageSwiper {
        let swiper = PageSwiper(pageCount: 7)
        swiper.width = 400
        swiper.begin(on: page)
        return swiper
    }

    /// Settles the spring, a frame at a time at 120 Hz, and returns the page it landed on and
    /// whether the pages ever went past the next page and back.
    private func settle(_ swiper: PageSwiper, from start: TimeInterval) -> (page: Int?, overshot: Bool) {
        var overshot = false
        for frame in 1...240 {
            if let page = swiper.step(to: start + Double(frame) / 120) {
                return (page, overshot)
            }
            if abs(swiper.offset) > swiper.width + 0.5 { overshot = true }
        }
        return (nil, overshot)
    }

    @Test func thePagesMovePointForPointWithTheFingers() {
        let swiper = swiper(on: 3)
        swiper.track(-30, at: 0)
        swiper.track(-45, at: 0.016)
        #expect(swiper.offset == -75)
        #expect(swiper.shownOffset == -75)
    }

    @Test func pastTheFirstPageTheyMoveLessAndLess() {
        let swiper = swiper(on: 0)
        swiper.track(100, at: 0)
        #expect(swiper.shownOffset > 0 && swiper.shownOffset < 60)
        swiper.track(200, at: 0.016)
        #expect(swiper.shownOffset < 160)
    }

    @Test func letGoOfPastHalfwayItGoesOn() {
        let swiper = swiper(on: 3)
        swiper.track(-250, at: 0)
        swiper.release(at: 0.5, springStart: 10)
        #expect(settle(swiper, from: 10).page == 4)
    }

    @Test func letGoOfShortOfHalfwayItComesBack() {
        let swiper = swiper(on: 3)
        swiper.track(-150, at: 0)
        swiper.release(at: 0.5, springStart: 10)
        #expect(settle(swiper, from: 10).page == 3)
    }

    @Test func aFlickGoesOnEvenFromAShortWay() {
        let swiper = swiper(on: 3)
        swiper.track(-20, at: 0)
        swiper.track(-20, at: 0.016)
        swiper.track(-20, at: 0.032)
        swiper.release(at: 0.04, springStart: 10)
        let landed = settle(swiper, from: 10)
        #expect(landed.page == 4)
        #expect(!landed.overshot)
    }

    @Test func aFlickBackStays() {
        let swiper = swiper(on: 3)
        swiper.track(-150, at: 0)
        swiper.track(30, at: 0.5)
        swiper.track(30, at: 0.516)
        swiper.release(at: 0.53, springStart: 10)
        #expect(settle(swiper, from: 10).page == 3)
    }

    /// A long swipe goes on past the next page.
    @Test func aSwipeLongerThanAPageGoesOn() {
        let swiper = swiper(on: 1)
        swiper.track(-450, at: 0)
        #expect(swiper.page == 2)
        #expect(swiper.offset == -50)
    }

    /// Fingers down while the pages settle stop them where they are.
    @Test func fingersDownCatchThePages() {
        let swiper = swiper(on: 3)
        swiper.track(-250, at: 0)
        swiper.release(at: 0.5, springStart: 10)
        _ = swiper.step(to: 10.05)
        let caught = swiper.offset
        swiper.catchPages()
        #expect(swiper.isTracking)
        #expect(!swiper.isSettling)
        #expect(swiper.offset == caught)
        swiper.track(-10, at: 1)
        #expect(swiper.offset == caught - 10)
    }

    /// The last page has none after it, flicked or not.
    @Test func theLastPageStays() {
        let swiper = swiper(on: 6)
        swiper.track(-300, at: 0)
        swiper.release(at: 0.01, springStart: 10)
        #expect(settle(swiper, from: 10).page == 6)
    }
}
#endif
