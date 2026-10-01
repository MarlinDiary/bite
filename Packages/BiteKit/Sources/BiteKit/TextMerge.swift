/// Merges two edits of the same text line by line, as `diff3` does. `base` is the text both
/// edits started from. Lines only one side changed take that side's change. Where both sides
/// changed the same lines differently, both versions are kept, this device's first, so nothing
/// typed on either is lost.
public enum TextMerge {
    public static func merge(base: String, local: String, remote: String) -> String {
        if local == remote || remote == base { return local }
        if local == base { return remote }
        let base = lines(base)
        let local = lines(local)
        let remote = lines(remote)
        let changes = (changes(from: base, to: local, matches(base, local), local: true)
            + changes(from: base, to: remote, matches(base, remote), local: false))
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var merged: [Substring] = []
        var position = 0
        var index = 0
        while index < changes.count {
            // Changes the two sides made to the same lines go together; changes next to each other
            // don't touch, and each goes in.
            var group = [changes[index]]
            index += 1
            while index < changes.count, group.contains(where: { $0.overlaps(changes[index]) }) {
                group.append(changes[index])
                index += 1
            }
            let start = group.map(\.start).min()!, end = group.map(\.end).max()!
            merged += base[position..<start]
            let mine = version(of: base, start..<end, with: group.filter(\.isLocal))
            let theirs = version(of: base, start..<end, with: group.filter { !$0.isLocal })
            if group.allSatisfy(\.isLocal) {
                merged += mine
            } else if !group.contains(where: \.isLocal) {
                merged += theirs
            } else {
                merged += mine
                if theirs != mine { merged += theirs }
            }
            position = end
        }
        merged += base[position...]
        return merged.joined(separator: "\n")
    }

    /// Lines `start..<end` of the text both started from, which one side replaced with `lines`.
    private struct Change {
        var start: Int
        var end: Int
        var lines: ArraySlice<Substring>
        var isLocal: Bool

        /// Whether the two changed the same lines, or both put lines in at the same place.
        func overlaps(_ other: Change) -> Bool {
            (start < other.end && other.start < end) || (start == end && other.start == other.end && start == other.start)
        }
    }

    /// One side's changes, between the lines it kept.
    private static func changes(from base: [Substring], to side: [Substring], _ matched: [Int?], local: Bool) -> [Change] {
        var changes: [Change] = []
        var b = 0, s = 0
        for i in 0...base.count {
            let j: Int
            if i < base.count {
                guard let kept = matched[i] else { continue }
                j = kept
            } else {
                j = side.count
            }
            if i > b || j > s {
                changes.append(Change(start: b, end: i, lines: side[s..<j], isLocal: local))
            }
            b = i + 1
            s = j + 1
        }
        return changes
    }

    /// Lines `range` of `base` as one side has them, its `changes` there made.
    private static func version(of base: [Substring], _ range: Range<Int>, with changes: [Change]) -> [Substring] {
        var lines: [Substring] = []
        var position = range.lowerBound
        for change in changes.sorted(by: { $0.start < $1.start }) {
            lines += base[position..<change.start]
            lines += change.lines
            position = change.end
        }
        lines += base[position..<range.upperBound]
        return lines
    }

    private static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// For each line of `old`, the line of `new` it's kept as, if it is: a longest common
    /// subsequence of the two.
    private static func matches(_ old: [Substring], _ new: [Substring]) -> [Int?] {
        var matched = [Int?](repeating: nil, count: old.count)
        // Lines the two have in common at the start and the end are matched as they are.
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] {
            matched[start] = start
            start += 1
        }
        var oldEnd = old.count, newEnd = new.count
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
            matched[oldEnd] = newEnd
        }
        guard oldEnd > start, newEnd > start else { return matched }
        // The rest as numbers, one for each different line, which compare faster than text.
        var numbers: [Substring: Int] = [:]
        func number(_ line: Substring) -> Int {
            if let number = numbers[line] { return number }
            numbers[line] = numbers.count
            return numbers.count - 1
        }
        let a = old[start..<oldEnd].map(number)
        let b = new[start..<newEnd].map(number)
        for (x, y) in longestCommonSubsequence(a, b) {
            matched[start + x] = start + y
        }
        return matched
    }

    /// Past this many lines changed between the two, the lines in between aren't matched up:
    /// both sides then keep all of theirs.
    static let mostChangesMatched = 1000

    /// The pairs of positions of a longest common subsequence of `a` and `b`, in order, found as
    /// Myers does, in time and space that grow with how much changed rather than how long the
    /// texts are.
    private static func longestCommonSubsequence(_ a: [Int], _ b: [Int]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        // Two texts that differ in length by more lines than are matched need at least that many
        // changes: there's no looking.
        guard abs(n - m) <= mostChangesMatched else { return [] }
        let limit = min(n + m, mostChangesMatched)
        // How far along each diagonal (x - y) the furthest path with `steps` changes gets, and
        // for every step, the diagonals that step could have come from.
        var furthest = [Int](repeating: 0, count: 2 * limit + 3)
        let center = limit + 1
        // Each step keeps only the diagonals it reached, copied: a slice would hold on to the
        // whole array.
        var trace: [[Int]] = []
        var reached = false
        search: for steps in 0...limit {
            trace.append(Array(furthest[(center - steps - 1)...(center + steps + 1)]))
            for diagonal in stride(from: -steps, through: steps, by: 2) {
                var x: Int
                if diagonal == -steps || (diagonal != steps && furthest[center + diagonal - 1] < furthest[center + diagonal + 1]) {
                    x = furthest[center + diagonal + 1]
                } else {
                    x = furthest[center + diagonal - 1] + 1
                }
                var y = x - diagonal
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                furthest[center + diagonal] = x
                if x >= n, y >= m {
                    reached = true
                    break search
                }
            }
        }
        guard reached else { return [] }
        // Back from the end along the steps taken, collecting the lines both have.
        var pairs: [(Int, Int)] = []
        var x = n, y = m
        for steps in stride(from: trace.count - 1, through: 0, by: -1) {
            let reachedBefore = trace[steps]
            func previous(_ diagonal: Int) -> Int { reachedBefore[diagonal + steps + 1] }
            let diagonal = x - y
            let cameDown = diagonal == -steps || (diagonal != steps && previous(diagonal - 1) < previous(diagonal + 1))
            let previousDiagonal = cameDown ? diagonal + 1 : diagonal - 1
            let previousX = previous(previousDiagonal)
            let previousY = previousX - previousDiagonal
            while x > previousX, y > previousY {
                x -= 1
                y -= 1
                pairs.append((x, y))
            }
            if steps > 0 {
                x = previousX
                y = previousY
            }
        }
        return pairs.reversed()
    }
}
