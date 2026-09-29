import SwiftUI

/// Visual states the placeholder sprite can express.
/// Mirrors (and will be driven by) the future Core session states.
enum YumiSpriteState: String, CaseIterable {
    case idle
    case working
    case approval
    case error
    case finished
}

/// The Yumi placeholder character.
///
/// Original technical placeholder — a rounded-square head with pill eyes,
/// drawn entirely in code (no assets, nothing from Coucou). Renders a single
/// visual state with breathing + blinking so the renderer pipeline
/// (Canvas + TimelineView) is exercised end to end. To be replaced by the
/// final Yumi character once the art direction is defined.
struct YumiSprite: View {
    let state: YumiSpriteState
    /// Body radius in points.
    var size: CGFloat = 24
    /// Optional look direction in [-1, 1]; eyes shift toward it.
    var lookX: CGFloat = 0

    var body: some View {
        TimelineView(.animation(paused: false)) { timeline in
            Canvas { context, canvasSize in
                let now = timeline.date.timeIntervalSinceReferenceDate
                var sprite = context
                sprite.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)

                let radius = size / 2
                // Breathing (gentle vertical squash, always alive)
                let breathe = 1 + sin(now * 1.8) * 0.035
                sprite.scaleBy(x: 2 - breathe, y: breathe)

                // Blink roughly every 3–5 s
                let blinkCycle = now.truncatingRemainder(dividingBy: 4)
                let blink: CGFloat = blinkCycle < 0.16 ? 1 - sin((blinkCycle / 0.16) * .pi) : 1

                drawSprite(context: &sprite, radius: radius,
                           tint: 0,
                           blink: blink,
                           happy: state == .finished || state == .idle)

                // State eyebrow/eyes accents
                drawStateAccent(context: &sprite, radius: radius,
                                state: state, now: now, lookX: lookX)
            }
        }
        .frame(width: size * 2.2, height: size * 2.2)
    }

    private func drawStateAccent(context: inout GraphicsContext, radius: CGFloat,
                                 state: YumiSpriteState, now: Double, lookX: CGFloat) {
        let ink = Color(red: 0.08, green: 0.12, blue: 0.12)

        switch state {
        case .working:
            // Three animated dots above the head
            for i in 0..<3 {
                let phase = (now * 2.4 - Double(i) * 0.22)
                    .truncatingRemainder(dividingBy: 1)
                let p = phase < 0 ? phase + 1 : phase
                let dotR = radius * 0.09 * (0.6 + 0.4 * max(0, sin(p * .pi * 2)))
                let dot = Path(ellipseIn: CGRect(
                    x: CGFloat(i - 1) * radius * 0.28 - dotR,
                    y: -radius * 1.35 - dotR,
                    width: dotR * 2, height: dotR * 2))
                context.fill(dot, with: .color(.white.opacity(0.9)))
            }
        case .approval:
            // Amber exclamation ring above the head
            let ringRect = CGRect(x: -radius * 0.22, y: -radius * 1.62,
                                  width: radius * 0.44, height: radius * 0.44)
            context.fill(Path(ellipseIn: ringRect), with: .color(.orange))
            context.draw(Text("!").font(.system(size: radius * 0.3, weight: .black))
                            .foregroundColor(.white),
                         at: CGPoint(x: 0, y: -radius * 1.4))
        case .error:
            // Red dot
            let dotRect = CGRect(x: -radius * 0.14, y: -radius * 1.5,
                                 width: radius * 0.28, height: radius * 0.28)
            context.fill(Path(ellipseIn: dotRect), with: .color(.red))
        case .finished, .idle:
            // Green check dot for finished, nothing for idle
            if state == .finished {
                let dotRect = CGRect(x: -radius * 0.14, y: -radius * 1.5,
                                     width: radius * 0.28, height: radius * 0.28)
                context.fill(Path(ellipseIn: dotRect), with: .color(.green))
            }
        }

        // Look direction: nudge pupils (kept subtle for the placeholder)
        _ = lookX
        _ = ink
    }
}
