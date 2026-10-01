import Foundation
import Testing
@testable import BiteKit

/// A page changed on two devices, merged line by line, with nothing typed on either lost.
struct TextMergeTests {
    /// Merges pages given as their lines, each ending in a line break as a page's do, so that no
    /// lines at all and one empty line aren't the same text.
    private func merge(_ base: [String], _ local: [String], _ remote: [String]) -> [String] {
        func text(_ lines: [String]) -> String { lines.map { $0 + "\n" }.joined() }
        var lines = TextMerge.merge(base: text(base), local: text(local), remote: text(remote)).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    @Test func changesToDifferentLinesBothGoIn() {
        #expect(merge(["a", "b", "c", "d"], ["a", "B", "c", "d"], ["a", "b", "c", "D"]) == ["a", "B", "c", "D"])
        #expect(merge(["a", "b", "c"], ["x", "a", "b", "c"], ["a", "b", "c", "y"]) == ["x", "a", "b", "c", "y"])
    }

    /// Changes to lines next to each other don't touch: each goes in, once.
    @Test func changesToNeighbouringLinesBothGoIn() {
        #expect(merge(["a", "b", "c", ""], ["a", "B", "c", ""], ["a", "b", "C", ""]) == ["a", "B", "C", ""])
        #expect(merge(["a", "b", "c"], ["a", "c"], ["a", "b", "C"]) == ["a", "C"])
        #expect(merge(["a", "b"], ["a", "new", "b"], ["a", "B"]) == ["a", "new", "B"])
    }

    @Test func onlyOneSideChangedTakesItsChange() {
        #expect(merge(["a", "b"], ["a", "b"], ["a", "c"]) == ["a", "c"])
        #expect(merge(["a", "b"], ["a", "c"], ["a", "b"]) == ["a", "c"])
    }

    @Test func theSameChangeOnBothGoesInOnce() {
        #expect(merge(["a", "b", "c"], ["a", "x", "c"], ["a", "x", "c"]) == ["a", "x", "c"])
        #expect(merge(["a"], ["a", "b"], ["a", "b"]) == ["a", "b"])
    }

    /// Both versions of a line changed on both devices are kept, this device's first.
    @Test func aLineChangedOnBothKeepsBoth() {
        #expect(merge(["a", "b", "c"], ["a", "mine", "c"], ["a", "theirs", "c"]) == ["a", "mine", "theirs", "c"])
        #expect(merge(["a"], ["a", "mine"], ["a", "theirs"]) == ["a", "mine", "theirs"])
    }

    /// A line deleted on one device and changed on the other stays, changed.
    @Test func aChangeOutlivesADeletion() {
        #expect(merge(["a", "b", "c"], ["a", "c"], ["a", "b!", "c"]) == ["a", "b!", "c"])
        #expect(merge(["a", "b", "c", "d"], ["a", "c", "d"], ["a", "b", "c", "D"]) == ["a", "c", "D"])
    }

    /// The first time, with nothing in common to start from, both pages are kept whole.
    @Test func withNothingInCommonBothAreKept() {
        #expect(merge([""], ["mine", ""], ["theirs", ""]) == ["mine", "theirs", ""])
    }

    @Test func emptyLinesAndTheLastNewlineStay() {
        let base = "a\n\nb\n"
        #expect(TextMerge.merge(base: base, local: "a\n\nb\nc\n", remote: "z\na\n\nb\n") == "z\na\n\nb\nc\n")
    }

    /// Changes to separate parts of a page, on random pages, go in as if made one after the other.
    @Test func randomChangesToSeparateLinesBothGoIn() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<2000 {
            let count = random.next(upTo: 30)
            let base = (0..<count).map { "line \($0)" }
            // Two stretches that don't overlap, maybe right next to each other, one changed on each
            // device. Two sets of lines put in at the same place go in this device's first, which
            // isn't what's worked out here.
            let firstStart = random.next(upTo: count + 1)
            let firstEnd = firstStart + random.next(upTo: count - firstStart + 1)
            let secondStart = firstEnd + random.next(upTo: count - firstEnd + 1)
            let secondEnd = secondStart + random.next(upTo: count - secondStart + 1)
            if firstStart == firstEnd, secondStart == secondEnd, firstEnd == secondStart { continue }
            let mine = (0..<random.next(upTo: 4)).map { "mine \($0)" }
            let theirs = (0..<random.next(upTo: 4)).map { "theirs \($0)" }
            var local = base
            local.replaceSubrange(firstStart..<firstEnd, with: mine)
            var remote = base
            remote.replaceSubrange(secondStart..<secondEnd, with: theirs)
            var expected = base
            expected.replaceSubrange(secondStart..<secondEnd, with: theirs)
            expected.replaceSubrange(firstStart..<firstEnd, with: mine)
            let swapped = random.next(upTo: 2) == 0
            #expect(swapped ? merge(base, remote, local) == expected : merge(base, local, remote) == expected,
                    "\(base) \(local) \(remote)")
        }
    }

    /// A long page with a few changes merges at once, and two long pages with nothing in common
    /// are kept whole without working out a match line by line.
    @Test func longPagesMergeQuickly() {
        let base = (0..<5000).map { "line \($0), with some words in it" }
        var local = base
        local[100] = "changed here"
        local.insert("new line", at: 2500)
        var remote = base
        remote[4000] = "changed there"
        remote.remove(at: 10)
        let start = ContinuousClock.now
        let merged = merge(base, local, remote)
        #expect(ContinuousClock.now - start < .milliseconds(300))
        #expect(merged.count == 5000)
        #expect(merged[99] == "changed here")
        #expect(merged.contains("new line") && merged.contains("changed there") && !merged.contains(base[10]))

        let mine = (0..<3000).map { "mine \($0)" }
        let theirs = (0..<3000).map { "theirs \($0)" }
        let rewritten = ContinuousClock.now
        #expect(merge(["old"], mine, theirs) == mine + theirs)
        #expect(ContinuousClock.now - rewritten < .milliseconds(300))
    }
}

/// The same numbers every run.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}
