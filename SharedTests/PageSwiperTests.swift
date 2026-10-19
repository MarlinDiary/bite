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

    /// A drag of `count` moves of `distance` points, 120 a second from `start`, slow enough to go
    /// as far as the scroll. Returns when the last came.
    @discardableResult
    private func drag(_ swiper: PageSwiper, by distance: CGFloat, count: Int, from start: TimeInterval = 0) -> TimeInterval {
        var time = start
        for _ in 0..<count {
            time += 1.0 / 120
            swiper.track(distance, at: time)
        }
        return time
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
        swiper.track(-3, at: 0)
        swiper.track(-4.5, at: 0.016)
        #expect(swiper.offset == -7.5)
        #expect(swiper.shownOffset == -7.5)
        drag(swiper, by: -5, count: 30, from: 0.016)
        #expect(swiper.offset == -157.5)
    }

    @Test func pastTheFirstPageTheyMoveLessAndLess() {
        let swiper = swiper(on: 0)
        let time = drag(swiper, by: 5, count: 20)
        #expect(swiper.shownOffset > 0 && swiper.shownOffset < 60)
        drag(swiper, by: 5, count: 40, from: time)
        #expect(swiper.shownOffset < 160)
    }

    @Test func letGoOfPastHalfwayItGoesOn() {
        let swiper = swiper(on: 3)
        drag(swiper, by: -5, count: 50)
        swiper.release(at: 1, springStart: 10)
        #expect(settle(swiper, from: 10).page == 4)
    }

    @Test func letGoOfShortOfHalfwayItComesBack() {
        let swiper = swiper(on: 3)
        drag(swiper, by: -5, count: 30)
        swiper.release(at: 1, springStart: 10)
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
        drag(swiper, by: -5, count: 30)
        swiper.track(15, at: 0.5)
        swiper.track(15, at: 0.516)
        swiper.release(at: 0.53, springStart: 10)
        #expect(settle(swiper, from: 10).page == 3)
    }

    /// A long drag goes on past the next page.
    @Test func aSwipeLongerThanAPageGoesOn() {
        let swiper = swiper(on: 1)
        drag(swiper, by: -5, count: 90)
        #expect(swiper.page == 2)
        #expect(abs(swiper.offset + 50) < 0.001)
    }

    /// A flick the system sped up goes one page, however fast: the pages go less and less of the
    /// scroll's way the faster it goes, and never past the next page before the fingers lift.
    @Test func aFlickTheSystemSpedUpGoesOnePage() {
        let swiper = swiper(on: 1)
        // 150 points every 8 milliseconds, for a tenth of a second: 1,500 of the scroll's points,
        // nearly four pages.
        var time = 0.0
        for _ in 0..<12 {
            time += 0.008
            swiper.track(-150, at: time)
        }
        #expect(swiper.page == 1)
        #expect(swiper.offset > -0.85 * 400)
        swiper.release(at: time + 0.004, springStart: 10)
        let landed = settle(swiper, from: 10)
        #expect(landed.page == 2)
        #expect(!landed.overshot)
    }

    /// Fingers down while the pages settle stop them where they are.
    @Test func fingersDownCatchThePages() {
        let swiper = swiper(on: 3)
        drag(swiper, by: -5, count: 50)
        swiper.release(at: 1, springStart: 10)
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
