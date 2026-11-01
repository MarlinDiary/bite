import Foundation

/// How loud what's heard is in three bands of pitch, low to high, a fiftieth of a second at a time,
/// for the bars that go with the voice while Bite records, each following a band, so they move
/// apart as the sounds said do, an "s" lifting the highest, an "o" the lowest (see
/// `RecordingWave`). Each band's level is how near it is to its own loudest of late, so the bars
/// rise and fall with the syllables however loud or far off the voice is; how far each is from the
/// others is drawn out a little; and the room's hush between words moves none of them. Used from
/// one thread at a time, the microphone's.
nonisolated final class VoiceMeter: @unchecked Sendable {
    /// A fiftieth of a second of 16 kHz samples.
    static let blockLength = 320
    static let blockDuration = 0.02

    /// Speech's own: below the voice's first formant, about it, and above, where "s" and "f" are.
    private var bands = [Band(low: 80, high: 400), Band(low: 400, high: 1500), Band(low: 1500, high: 6000)]
    /// Samples short of a block, kept for the next.
    private var leftover: [Double] = []

    /// Each whole fiftieth of a second in `audio`, 16 kHz mono 16-bit samples, as each band's level,
    /// from 0 to 1.
    func levels(of audio: Data) -> [[Double]] {
        var samples = leftover
        audio.withUnsafeBytes { raw in
            samples += raw.bindMemory(to: Int16.self).map { Double($0) / 32768 }
        }
        let blocks = samples.count / Self.blockLength
        leftover = Array(samples[(blocks * Self.blockLength)...])
        return (0..<blocks).map { number in
            let block = samples[(number * Self.blockLength)..<((number + 1) * Self.blockLength)]
            let whole = Self.decibels(block.reduce(0) { $0 + $1 * $1 } / Double(Self.blockLength))
            // From the room's hush, 50 dB below full scale, to a voice 15 dB above it.
            let speaking = min(1, max(0, (whole - Self.hush) / 15))
            let levels = bands.indices.map { index in
                let own = bands[index].decibels(of: block)
                bands[index].loudest = max(own, bands[index].loudest - Self.fallBack * Self.blockDuration, Self.hush)
                return min(1, max(0, 1 + (own - bands[index].loudest) / Self.range))
            }
            let mean = levels.reduce(0, +) / Double(levels.count)
            return levels.map { speaking * min(1, max(0, mean + Self.contrast * ($0 - mean))) }
        }
    }

    private static func decibels(_ meanSquare: Double) -> Double {
        10 * log10(max(meanSquare, 1e-12))
    }

    private static let hush = -50.0
    /// How far below its loudest of late a band is down to nothing, in decibels.
    private static let range = 24.0
    /// How quickly a band's loudest of late falls back, in decibels a second.
    private static let fallBack = 8.0
    /// How far the bands are drawn apart from all of them together.
    private static let contrast = 1.6

    private struct Band {
        /// Two high-pass sections at its bottom and two low-pass at its top, falling 24 dB an octave
        /// past each.
        var sections: [Biquad]
        /// Its loudest of late, in decibels.
        var loudest = VoiceMeter.hush

        init(low: Double, high: Double) {
            sections = [Biquad(.highPass, at: low), Biquad(.lowPass, at: high), Biquad(.highPass, at: low), Biquad(.lowPass, at: high)]
        }

        mutating func decibels(of block: ArraySlice<Double>) -> Double {
            var sum = 0.0
            for sample in block {
                var value = sample
                for index in sections.indices {
                    value = sections[index].filter(value)
                }
                sum += value * value
            }
            return VoiceMeter.decibels(sum / Double(block.count))
        }
    }

    /// A second-order Butterworth filter, as Robert Bristow-Johnson's cookbook has it.
    private struct Biquad {
        enum Kind { case lowPass, highPass }
        private let b0, b1, b2, a1, a2: Double
        private var z1 = 0.0
        private var z2 = 0.0

        init(_ kind: Kind, at frequency: Double, sampleRate: Double = 16000) {
            let w = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(w) / sqrt(2)
            let a0 = 1 + alpha
            let edge = kind == .lowPass ? 1 - cos(w) : -(1 + cos(w))
            b0 = abs(edge) / 2 / a0
            b1 = edge / a0
            b2 = b0
            a1 = -2 * cos(w) / a0
            a2 = (1 - alpha) / a0
        }

        mutating func filter(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }
}
