import Foundation
import Testing
@testable import Bite

/// How loud what's heard is in each band of pitch, for the "…" button's bars while Bite records
/// (see `RecordingWave`).
struct VoiceMeterTests {
    /// 16 kHz samples of each part in turn: a tone `decibels` below full scale, its waves running on
    /// from one part to the next, or with no tone, silence.
    private func samples(_ parts: [(frequency: Double, decibels: Double?, seconds: Double)]) -> [Int16] {
        var samples: [Int16] = []
        var phase = 0.0
        for part in parts {
            let amplitude = part.decibels.map { pow(10, $0 / 20) * 2.0.squareRoot() } ?? 0
            for _ in 0..<Int(part.seconds * 16000) {
                samples.append(Int16(amplitude * sin(phase) * 32767))
                phase += 2 * .pi * part.frequency / 16000
            }
        }
        return samples
    }

    private func data(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// What a meter makes of `samples`, handed to it a tenth of a second at a time, as the
    /// microphone hands them on.
    private func levels(_ samples: [Int16]) -> [[Double]] {
        let meter = VoiceMeter()
        return stride(from: 0, to: samples.count, by: 1600).flatMap { start in
            meter.levels(of: data(Array(samples[start..<min(start + 1600, samples.count)])))
        }
    }

    /// Each whole fiftieth of a second gets a level for each of the three bars; what's short of one
    /// waits for the next audio.
    @Test func eachFiftiethOfASecondHasALevelForEachBar() {
        let meter = VoiceMeter()
        let first = meter.levels(of: data(samples([(200, -20, 1000.0 / 16000)])))
        #expect(first.count == 3)
        #expect(first.allSatisfy { $0.count == 3 && $0.allSatisfy { (0...1).contains($0) } })
        // 40 samples left over and 600 more: two fiftieths.
        #expect(meter.levels(of: data([Int16](repeating: 0, count: 600))).count == 2)
    }

    /// Silence, and a room's hush 60 dB below full scale, move none of the bars.
    @Test func silenceAndTheRoomsHushMoveNothing() {
        #expect(levels(samples([(0, nil, 1)])).allSatisfy { $0 == [0, 0, 0] })
        var seed: UInt32 = 1
        let hush = (0..<16000).map { _ -> Int16 in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int16(Int32(bitPattern: seed >> 1) % 113 - 56)
        }
        #expect(levels(hush).allSatisfy { $0 == [0, 0, 0] })
    }

    /// A low sound lifts the low bar, not the high one; a high sound, as of an "s", the high one and
    /// not the low.
    @Test func aLowSoundLiftsTheLowBarAndAHighOneTheHigh() throws {
        let low = try #require(levels(samples([(150, -20, 1)])).last)
        #expect(low[0] == 1)
        #expect(low[2] == 0)
        let high = try #require(levels(samples([(3000, -20, 1)])).last)
        #expect(high[2] == 1)
        #expect(high[0] == 0)
    }

    /// A bar goes with its band next to its loudest of late: a syllable 12 dB quieter stands lower,
    /// till the band's loudest has fallen back to it, a second and a half on.
    @Test func aQuieterSyllableStandsLowerTillItsTheLoudestOfLate() throws {
        let all = levels(samples([(150, -20, 1), (150, -32, 3)]))
        #expect(all[49][0] == 1)
        #expect(all[51][0] > 0.3)
        #expect(all[51][0] < 0.9)
        #expect(try #require(all.last)[0] == 1)
    }
}
