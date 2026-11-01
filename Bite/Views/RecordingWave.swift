import SwiftUI

/// The "…" button's dots while Bite records: three bars that go with the voice, as the Dynamic
/// Island's do with music playing (user, 2026-11-01). Each stands where a dot of the button's
/// ellipsis does, as wide, and grows up and down from its middle with a band of what's heard, low
/// to high from left to right (see `VoiceMeter`), so they move apart as the sounds said do, a
/// fiftieth of a second at a time, a little behind. In silence they barely stir, a little longer
/// than the dots, so it still shows it's listening. Started, the dots draw out into bars; stopped,
/// they draw back into dots. All of it goes as springs that don't overshoot, setting off and
/// settling gently.
struct RecordingWave: View {
    /// Whether it's recording: the bars draw back into dots once it isn't.
    let isOn: Bool
    @State private var motion = WaveMotion()
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let drawn = motion.drawn(at: timeline.date, isOn: isOn, isCalm: reducesMotion)
                for (index, drawn) in drawn.enumerated() {
                    let length = Self.width + CGFloat(drawn) * (Self.longest - Self.width)
                    let x = size.width / 2 + CGFloat(index - 1) * Self.spacing
                    let bar = CGRect(x: x - Self.width / 2, y: (size.height - length) / 2 + Self.below, width: Self.width, height: length)
                    context.fill(Path(roundedRect: bar, cornerRadius: Self.width / 2), with: .foreground)
                }
            }
            // Room to spare round the label.
            .padding(-4)
        }
    }

    // The ellipsis's dots, at 17 points semibold, as measured on the screen: 3.5 across, their
    // middles 6.24 apart, a quarter of a point below the label's middle. The bars start from them
    // exactly, nothing shifting as the one takes over from the other.
    static let width: CGFloat = 3.5
    static let spacing: CGFloat = 6.24
    static let below: CGFloat = 0.23
    /// How long the bars grow, the voice at its loudest.
    static let longest: CGFloat = 13
}

/// How far each bar is drawn out, from one frame to the next: each follows its band of what was
/// heard a moment before as a spring that doesn't overshoot, quick to rise and slower to fall back,
/// as a level meter's do.
@MainActor
private final class WaveMotion {
    /// From the dots, 0, to bars, 1.
    private var presence = 0.0
    private var presenceSpeed = 0.0
    /// Each bar's length past a dot's, from 0 to the longest, and how fast it's changing.
    private var drawn = [0.0, 0.0, 0.0]
    private var speeds = [0.0, 0.0, 0.0]
    private var last: Date?

    func drawn(at date: Date, isOn: Bool, isCalm: Bool) -> [Double] {
        let step = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        let time = date.timeIntervalSinceReferenceDate
        Self.spring(&presence, &presenceSpeed, to: isOn ? 1 : 0, rate: 14, over: step)
        // What was heard an eighth of a second ago: it comes a tenth of a second at a time.
        let heard = VoiceInput.shared.levels(at: time - 0.12) ?? []
        let middle = Double(drawn.count - 1) / 2
        for bar in drawn.indices {
            let offset = Double(bar)
            // Barely stirring, a slow wave along them.
            let stir = isCalm ? 0.2 : 0.2 + 0.06 * sin(time * 2 * .pi / 1.6 - offset * 3.6 / Double(drawn.count))
            // Calm, they go together, with the voice's loudness.
            let level = heard.isEmpty ? 0 : isCalm ? heard.reduce(0, +) / Double(heard.count) : heard[min(bar, heard.count - 1)]
            // The middle one a little longer, as a voice's shape is.
            let weight = 1 - 0.18 * abs(offset - middle) / max(middle, 1)
            let target = presence * (stir + (1 - stir) * weight * level)
            Self.spring(&drawn[bar], &speeds[bar], to: target, rate: target > drawn[bar] ? 30 : 12, over: step)
        }
        return drawn
    }

    /// Moves `value` toward `target` as a spring that doesn't overshoot, `rate` its natural
    /// frequency, in radians a second; never past 0 or 1.
    private static func spring(_ value: inout Double, _ speed: inout Double, to target: Double, rate: Double, over step: Double) {
        let off = value - target
        let fade = exp(-rate * step)
        let pull = (speed + rate * off) * step
        value = target + (off + pull) * fade
        speed = (speed - rate * pull) * fade
        if value < 0 || value > 1 {
            value = min(1, max(0, value))
            speed = 0
        }
    }
}
