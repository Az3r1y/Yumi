import CoreGraphics

// The mock-up (design/yumi/maquette/reference.html) animates the face with CSS transitions
// and keyframes. These three helpers reproduce them, so the same durations and curves can
// be written here as they are written there.

/// A CSS `cubic-bezier(x1, y1, x2, y2)` timing function.
struct YumiCurve: Sendable {
    let x1, y1, x2, y2: CGFloat

    init(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    static let linear    = YumiCurve(0, 0, 1, 1)
    static let ease      = YumiCurve(0.25, 0.1, 0.25, 1)
    static let easeOut   = YumiCurve(0, 0, 0.58, 1)
    static let easeInOut = YumiCurve(0.42, 0, 0.58, 1)
    /// `--spring` of the mock-up: overshoots a little, then settles.
    static let spring    = YumiCurve(0.32, 1.22, 0.42, 1)
    /// Eyelids and eye scale.
    static let lid       = YumiCurve(0.3, 1.3, 0.5, 1)
    /// The rim drawing itself when the light comes on.
    static let draw      = YumiCurve(0.6, 0, 0.2, 1)

    func callAsFunction(_ p: CGFloat) -> CGFloat {
        if p <= 0 { return 0 }
        if p >= 1 { return 1 }
        func bezier(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
            3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u
        }
        // x(u) is monotonic for valid curves: bisect to find u, then read y(u)
        var lo: CGFloat = 0, hi: CGFloat = 1, u = p
        for _ in 0..<24 {
            let x = bezier(u, x1, x2)
            if abs(x - p) < 1e-5 { break }
            if x < p { lo = u } else { hi = u }
            u = (lo + hi) / 2
        }
        return bezier(u, y1, y2)
    }
}

/// A CSS transition on one number: when the target changes, the value leaves from where
/// it is and reaches the target after `duration`, along `curve`.
struct YumiTransition {
    private var from: CGFloat
    private var to: CGFloat
    private var start: Double = 0
    private var duration: Double = 0
    private var curve = YumiCurve.ease

    init(_ value: CGFloat) { from = value; to = value }

    var target: CGFloat { to }

    mutating func set(_ value: CGFloat, at now: Double, over duration: Double, _ curve: YumiCurve) {
        guard value != to else { return }
        from = self.value(at: now)
        to = value
        start = now
        self.duration = duration
        self.curve = curve
    }

    /// True while the value is still on its way to the target.
    func isActive(at now: Double) -> Bool { duration > 0 && now < start + duration }

    /// Changes the value at once (`transition: none`).
    mutating func jump(_ value: CGFloat) { from = value; to = value; duration = 0 }

    func value(at now: Double) -> CGFloat {
        guard duration > 0 else { return to }
        return from + (to - from) * curve(CGFloat((now - start) / duration))
    }
}

/// CSS keyframes for one property: `stops` are (offset 0…1, value) pairs, and `curve` is
/// applied between each pair of neighbours, as `animation-timing-function` does.
func yumiKeyframes(_ p: CGFloat, _ stops: [(CGFloat, CGFloat)], _ curve: YumiCurve) -> CGFloat {
    guard let first = stops.first, let last = stops.last else { return 0 }
    if p <= first.0 { return first.1 }
    if p >= last.0 { return last.1 }
    for i in 1..<stops.count where p <= stops[i].0 {
        let a = stops[i - 1], b = stops[i]
        let span = b.0 - a.0
        return span > 0 ? a.1 + (b.1 - a.1) * curve((p - a.0) / span) : b.1
    }
    return last.1
}
