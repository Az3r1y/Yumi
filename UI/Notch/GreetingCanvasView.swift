import SwiftUI

/// Scripted 4.6 s greeting animation for the Yumi placeholder sprite.
///
/// New Yumi animation (the choreography is intentionally simpler than
/// Coucou's greeting — this is a placeholder until the real character and
/// its introduction are designed). Timeline runs once per `runID`.
struct GreetingCanvasView: View {
    /// Incremented each time the greeting starts; restarts the timeline.
    let runID: Int

    /// Greeting timeline (seconds, from Coucou's proven rhythm).
    private enum T {
        static let grow = 0.45
        static let pop0 = 1.36
        static let pop1 = 1.52
        static let tint0 = 3.85
        static let tint1 = 4.15
        static let end = 4.60
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startDate)
                guard t >= 0 else { return }
                draw(at: min(t, T.end + 1), in: context, size: size)
            }
        }
        .onChange(of: runID) { _, _ in
            restart()
        }
        .onAppear {
            restart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            completionTask?.cancel()
            completionTask = nil
        }
    }

    /// Real clock captured when the greeting starts — the timeline restarts
    /// from it on each new run.
    @State private var startDate: Date = .now
    @State private var completionTask: Task<Void, Never>?

    private func restart() {
        startDate = .now
        scheduleCompletion()
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(T.end))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .greetComplete, object: nil)
        }
    }

    // MARK: - Drawing

    private func draw(at t: Double, in context: GraphicsContext, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2

        // Grow in
        let growT = clamp((t - 0) / T.grow, 0, 1)
        let scale = 0.05 + 0.95 * easeOutBack(growT)

        // Pop (little hop) at 1.36–1.52
        let popT = clamp((t - T.pop0) / (T.pop1 - T.pop0), 0, 1)
        let hop = -sin(popT * .pi) * 10

        // Tint pulse near the end (friendly "I'm here")
        let tintT = clamp((t - T.tint0) / (T.tint1 - T.tint0), 0, 1)
        let tint = sin(tintT * .pi)

        // Draw the sprite through its public parameter API so the greeting
        // exercises the same renderer as the notch will.
        var sprite = context
        sprite.translateBy(x: cx, y: cy + hop)
        sprite.scaleBy(x: scale, y: scale)
        drawSprite(context: &sprite, radius: 32,
                   tint: tint * 0.5,
                   blink: blinkAmount(t: t),
                   happy: t > T.pop0)
    }

    /// Blink twice during the greeting (0.55 s and 1.50 s), like the FSM expects.
    private func blinkAmount(t: Double) -> CGFloat {
        for blinkTime in [0.55, 1.50] {
            let bt = (t - blinkTime) / 0.20
            if bt >= 0 && bt <= 1 {
                return 1 - sin(bt * .pi) // 1 → closed → 1
            }
        }
        return 1
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v))
    }

    private func easeOutBack(_ t: Double) -> CGFloat {
        let c1 = 1.70158, c3 = c1 + 1
        let x = max(0, min(1, t))
        return CGFloat(1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2))
    }
}

// MARK: - Shared sprite drawing (placeholder renderer)

/// Draws the Yumi placeholder sprite centered at the context origin.
/// Shared by `YumiSprite` (live states) and `GreetingCanvasView` (greeting)
/// so both exercise the same renderer.
///
/// Design (original, simple, replaceable): a rounded-square head with two
/// pill eyes and a small mouth, drawn entirely in code — no assets.
/// Parameters keep it state-driven: tint color, eye openness, happiness.
func drawSprite(context: inout GraphicsContext, radius: CGFloat,
                tint: CGFloat, blink: CGFloat, happy: Bool) {
    let bodyRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
    let body = Path(roundedRect: bodyRect, cornerRadius: radius * 0.42)

    // Body — soft teal gradient, warm tint overlay while greeting
    context.fill(body, with: .linearGradient(
        Gradient(colors: [Color(red: 0.42, green: 0.78, blue: 0.72),
                          Color(red: 0.25, green: 0.58, blue: 0.55)]),
        startPoint: CGPoint(x: 0, y: -radius),
        endPoint: CGPoint(x: 0, y: radius)))
    if tint > 0.01 {
        context.fill(body, with: .color(Color.yellow.opacity(Double(tint) * 0.35)))
    }

    // Eyes — two pills that blink (open → closed → open)
    let eyeW = radius * 0.22
    let eyeH = radius * 0.30 * blink
    let eyeOffset = radius * 0.34
    for side in [-1.0, 1.0] {
        let eyeRect = CGRect(x: CGFloat(side) * eyeOffset - eyeW / 2,
                             y: -radius * 0.25 - eyeH / 2,
                             width: eyeW,
                             height: max(eyeH, eyeW * 0.3))
        let eye = Path(roundedRect: eyeRect, cornerRadius: eyeW / 2)
        context.fill(eye, with: .color(Color(red: 0.08, green: 0.12, blue: 0.12)))
    }

    // Mouth — small happy arc or neutral line
    let mouthY = radius * 0.25
    var mouth = Path()
    if happy {
        mouth.addArc(center: CGPoint(x: 0, y: mouthY - 2),
                     radius: radius * 0.18,
                     startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
    } else {
        mouth.move(to: CGPoint(x: -radius * 0.14, y: mouthY))
        mouth.addLine(to: CGPoint(x: radius * 0.14, y: mouthY))
    }
    context.stroke(mouth,
                   with: .color(Color(red: 0.08, green: 0.12, blue: 0.12)),
                   style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))
}
