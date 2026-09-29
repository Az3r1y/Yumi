import Foundation

/// Deterministic blink scheduling: given the monotonic time, tells whether the
/// eyes are currently closed and when the next blink starts. Pure and
/// testable — every character instance uses the same rhythm (slightly random
/// per anchor, stable over time).
enum CharacterEyeAnimation {

    /// Returns eye openness in [0, 1] at time `t` (seconds since anchor).
    static func openness(at t: TimeInterval, anchor: TimeInterval = 0) -> CGFloat {
        let next = nextBlink(after: t, anchor: anchor)
        let bt = (t - next) / blinkDuration
        if bt >= 0 && bt <= 1 {
            return 1 - sin(bt * .pi)  // 1 → 0 → 1
        }
        return 1
    }

    /// Start time of the blink covering time `t` (or the next one).
    static func nextBlink(after t: TimeInterval, anchor: TimeInterval = 0) -> TimeInterval {
        // Blinks at staggered intervals: 2.2s, then 2.2–5.4s gaps, with an
        // occasional double-blink (22% chance encoded deterministically).
        var time = anchor + 2.2
        while time < t {
            let index = Int((time - anchor) / 0.7)
            let random = pseudoRandom(index)
            let gap = random < 0.22 ? 0.35 : 2.2 + random * 3.2
            time += gap
        }
        return time
    }

    static let blinkDuration: TimeInterval = 0.2

    /// Stable pseudo-random in [0, 1) from an integer seed.
    private static func pseudoRandom(_ seed: Int) -> Double {
        var x = seed &* 747796405 &+ 2891336453
        x = (x >> ((x >> 28) + 4)) ^ x &* 277803737
        x = (x >> 22) ^ x
        return Double(x & 0xFFFFFFF) / Double(0xFFFFFFF + 1)
    }
}
