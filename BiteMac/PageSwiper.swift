import Foundation

/// The pages under two fingers sliding sideways on a trackpad. They move point for point with
/// the fingers, as the phone's pager does under a finger, and let go of, they settle on a page
/// with a spring that carries on at the fingers' speed and never overshoots. Fingers coming down
/// again catch the pages where they are.
///
/// AppKit's own swipe tracking, as Safari uses to go back, moved the pages less than the fingers
/// and settled them slowly.
@MainActor
final class PageSwiper {
    let pageCount: Int
    /// A page's width, which a whole swipe moves.
    var width: CGFloat = 400

    /// The page the pages are measured from, and how far it has moved right, in points: above 0
    /// the page before shows at its left, below 0 the page after at its right.
    private(set) var page = 0
    private(set) var offset: CGFloat = 0
    private(set) var isTracking = false
    var isSettling: Bool { spring != nil }
    var isActive: Bool { isTracking || isSettling }

    /// The fingers' last moves, for their speed as they let go.
    private var moves: [(distance: CGFloat, time: TimeInterval)] = []
    /// The scroll's last moves as the system sent them, for how fast it goes, and when the first
    /// came (see `easing`).
    private var scrolls: [(time: TimeInterval, distance: CGFloat)] = []
    private var began: TimeInterval = 0
    private var spring: (from: CGFloat, target: CGFloat, velocity: CGFloat, start: TimeInterval)?

    /// How long the spring takes to settle, about as long as the phone's pager.
    static let response: TimeInterval = 0.3
    /// Slower than this, in points a second, letting go settles on whichever page is mostly on
    /// screen; faster, a flick goes on to the next.
    static let flickSpeed: CGFloat = 250
    /// Up to this speed, in pages a second, the pages go as far as the scroll; faster, less and
    /// less, never past `topPagesPerSecond` (see `easing`).
    static let fullPagesPerSecond: CGFloat = 3.7
    static let topPagesPerSecond: CGFloat = 5.5

    init(pageCount: Int) {
        self.pageCount = pageCount
    }

    func begin(on page: Int) {
        self.page = page
        offset = 0
        spring = nil
        moves = []
        scrolls = []
        isTracking = true
    }

    /// The pages put down as they are, the panel going mid-swipe.
    func stop() {
        isTracking = false
        spring = nil
        moves = []
        scrolls = []
        offset = 0
    }

    /// Fingers down while the pages settle: they stop where they are, to be moved on from there.
    func catchPages() {
        guard isSettling else { return }
        spring = nil
        moves = []
        scrolls = []
        isTracking = true
    }

    func track(_ distance: CGFloat, at time: TimeInterval) {
        guard isTracking else { return }
        let distance = distance * easing(distance, at: time)
        offset += distance
        moves.append((distance, time))
        moves.removeAll { time - $0.time > 0.1 }
        // A swipe longer than a page goes on to the page after it.
        if offset <= -width, page < pageCount - 1 {
            page += 1
            offset += width
        } else if offset >= width, page > 0 {
            page -= 1
            offset -= width
        }
    }

    /// How much of a scroll's move the pages go. The system speeds a scroll up the faster the
    /// fingers go, as much as 38 times their way when flicked (measured on a MacBook Pro's
    /// trackpad), and about one swipe in four flew two pages or more. Slow and medium drags go as
    /// far as the scroll; faster, the pages go less and less further: of 85 swipes recorded and
    /// replayed, every flick went one page, at most 0.78 of the way there before the fingers
    /// lifted, and drags as far as before.
    private func easing(_ distance: CGFloat, at time: TimeInterval) -> CGFloat {
        // The swipe's first move came over the frame before.
        if scrolls.isEmpty { began = time - 1.0 / 120 }
        scrolls.append((time, abs(distance)))
        scrolls.removeAll { time - $0.time > 0.1 }
        // How fast the scroll goes, over its last few moves.
        let span = max(min(time - began, 0.033), 1.0 / 120)
        let speed = scrolls.filter { time - $0.time < span }.reduce(0) { $0 + $1.distance } / CGFloat(span)
        let full = Self.fullPagesPerSecond * width, top = Self.topPagesPerSecond * width
        guard speed > full, top > full else { return 1 }
        return (full + (top - full) * tanh((speed - full) / (top - full))) / speed
    }

    /// Where the pages are drawn. Past the first page or the last they move less and less, as
    /// a scroll view's content does.
    var shownOffset: CGFloat {
        let isPastEnd = (page == 0 && offset > 0) || (page == pageCount - 1 && offset < 0)
        guard isPastEnd, width > 0 else { return offset }
        let distance = abs(offset)
        return (offset < 0 ? -1 : 1) * (1 - 1 / (distance * 0.55 / width + 1)) * width
    }

    /// The fingers lift at `time`, in the moves' clock; the spring starts at `start`, in its own.
    func release(at time: TimeInterval, springStart start: TimeInterval) {
        guard isTracking else { return }
        isTracking = false
        let recent = moves.filter { time - $0.time <= 0.1 }
        var velocity = recent.isEmpty ? 0 : recent.map(\.distance).reduce(0, +) / CGFloat(max(time - recent[0].time, 1.0 / 60))
        var direction: CGFloat = 0
        if abs(velocity) > Self.flickSpeed {
            direction = velocity > 0 ? 1 : -1
            // Flicked back toward the page it came from: it stays there.
            if direction * offset < 0 { direction = 0 }
        } else if abs(offset) > width / 2 {
            direction = offset > 0 ? 1 : -1
        }
        if (direction > 0 && page == 0) || (direction < 0 && page == pageCount - 1) {
            direction = 0
        }
        let target = direction * width
        // Faster than this toward the page, the spring would go past it and back.
        let fastest = CGFloat(2 * Double.pi / Self.response) * abs(target - offset)
        if (target - offset) * velocity > 0 {
            velocity = min(max(velocity, -fastest), fastest)
        }
        spring = (offset, target, velocity, start)
    }

    /// Moves the spring on to `time`. Returns the page landed on once the pages have settled.
    func step(to time: TimeInterval) -> Int? {
        guard let spring else { return nil }
        // Critically damped: as fast as it can be without going past the page and back.
        let omega = 2 * Double.pi / Self.response
        let t = max(0, time - spring.start)
        let start = Double(spring.from - spring.target)
        let speed = Double(spring.velocity)
        let rate = speed + omega * start
        let decay = exp(-omega * t)
        let distance = (start + rate * t) * decay
        let velocity = (speed - omega * rate * t) * decay
        offset = spring.target + CGFloat(distance)
        guard abs(distance) < 0.5, abs(velocity) < 20 else { return nil }
        self.spring = nil
        if spring.target > 0 {
            page -= 1
        } else if spring.target < 0 {
            page += 1
        }
        offset = 0
        return page
    }
}
