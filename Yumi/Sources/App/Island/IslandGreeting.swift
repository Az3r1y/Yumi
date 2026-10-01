import SwiftUI

// The wide greeting of the launch (`.greet` in the mock-up, 420 × 168): a halo behind Yumi,
// his name letter by letter, a line under it, and the modules he watches. Yumi himself is
// the island's one character, drawn above; this layer only holds what surrounds him.

struct IslandGreetingLayer: View {
    let phase: IslandModel.GreetingPhase
    let modules: [ModuleSnapshot]
    /// Extra distance from the top when the notch is taller than the mock-up's.
    let drop: CGFloat

    private var glowOn: Bool { phase.lit && !phase.bye }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // `.g-glow`: centred on Yumi (118, 96), 320 × 240, blooms when the light comes on
            EllipticalGradient(
                stops: [
                    .init(color: Color(red: 139 / 255, green: 108 / 255, blue: 255 / 255).opacity(0.46), location: 0),
                    .init(color: Color(red: 91 / 255, green: 140 / 255, blue: 255 / 255).opacity(0.18), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
            )
            .frame(width: 320, height: 240)
            .scaleEffect(phase.lit ? 1 : 0.4)
            .animation(.islandSpring(1), value: phase.lit)
            .opacity(glowOn ? 1 : 0)
            .animation(.islandEase(phase.bye ? 0.22 : 0.8), value: glowOn)
            .position(x: 118, y: 96 + drop)

            // `.g-word`: 800 46px/1, each letter with its own gradient, 75 ms apart
            HStack(spacing: 0) {
                ForEach(Array("Yumi".enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .font(IslandTheme.round(46, .heavy))
                        .tracking(-0.92)
                        .foregroundStyle(LinearGradient(
                            stops: [
                                .init(color: IslandTheme.blue, location: 0),
                                .init(color: IslandTheme.violet, location: 0.55),
                                .init(color: IslandTheme.pink, location: 1),
                            ],
                            // 120deg
                            startPoint: UnitPoint(x: 0.07, y: 0.25), endPoint: UnitPoint(x: 0.93, y: 0.75)))
                        .modifier(LetterIn(on: phase.say, duration: 0.55, delay: Double(index) * 0.075))
                }
            }
            .fixedSize()
            // The mock-up's line box is 46 high; a text view is taller by its leading
            .frame(height: 46)
            .offset(x: 208, y: 46 + drop)
            .opacity(phase.bye ? 0 : 1)
            .animation(.islandEase(0.22), value: phase.bye)

            // `.g-tag`
            Text("Je garde un œil sur tout")
                .font(IslandTheme.round(12, .semibold))
                .foregroundStyle(IslandTheme.muted)
                .fixedSize()
                .modifier(LetterIn(on: phase.say, duration: 0.5, delay: 0.38))
                .offset(x: 210, y: 98 + drop)
                .opacity(phase.bye ? 0 : 1)
                .animation(.islandEase(0.22), value: phase.bye)

            // `.g-mods`: left 204, top 121, right 12, wrapping, 95 ms apart
            FlowLayout(spacing: 9, lineSpacing: 4) {
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    HStack(spacing: 0) {
                        ModuleDot(color: Color(hex: module.colorHex))
                        Text(module.name)
                            .font(IslandTheme.round(10.5, .bold))
                            .foregroundStyle(IslandTheme.muted)
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .modifier(LetterIn(on: phase.mods, duration: 0.42, delay: Double(index) * 0.095))
                }
            }
            .frame(width: IslandConst.greetWidth - 204 - 12, alignment: .leading)
            .offset(x: 204, y: 121 + drop)
            .opacity(phase.bye ? 0 : 1)
            .animation(.islandEase(0.22), value: phase.bye)
        }
        .frame(width: IslandConst.greetWidth, height: IslandConst.greetHeight + drop, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// `@keyframes letter { from { opacity: 0; transform: translateY(16px) scale(.6) } to { opacity: 1; transform: none } }`
private struct LetterIn: ViewModifier {
    let on: Bool
    let duration: Double
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .scaleEffect(on ? 1 : 0.6)
            .offset(y: on ? 0 : 16)
            .animation(on ? .islandSpring(duration).delay(delay) : nil, value: on)
    }
}

// MARK: - Rings and sparks (`#fx`)

/// Three rings and twelve dots burst from Yumi when the light comes on. Drawn inside the
/// island, so the island's edge cuts them, as `overflow: hidden` does in the mock-up.
struct IslandSparks: View {
    let start: Date?
    var scale: CGFloat = 1
    /// Centre of the burst, in island coordinates: Yumi's seat in the greeting.
    let center: CGPoint

    private static let colors = [IslandTheme.blue, IslandTheme.violet, IslandTheme.pink]
    /// `cubic-bezier(.2, .7, .3, 1)`
    private static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.7),
                                                endControlPoint: UnitPoint(x: 0.3, y: 1))
    /// Last ring: 0.26 s delay + 1 s
    private static let length = 1.3

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, _ in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t <= Self.length else { return }

                // `@keyframes ring { 0% { opacity: .9; transform: scale(.5) } 100% { opacity: 0; transform: scale(3.4) } }`, 1 s
                for i in 0..<3 {
                    let local = t - Double(i) * 0.13
                    guard local >= 0, local <= 1 else { continue }
                    let p = Self.curve.value(at: local)
                    let scale = (0.5 + (3.4 - 0.5) * p) * self.scale
                    let radius = 32 * scale
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: scale, dy: scale)),
                                   with: .color(Self.colors[i].opacity(0.9 * (1 - p))),
                                   lineWidth: 2 * scale)
                }

                // `@keyframes fly`: from 34 to 150 away, shrinking to .3, fading, .85 s
                for i in 0..<12 {
                    let local = (t - Double(i % 4) * 0.03) / 0.85
                    guard local >= 0, local <= 1 else { continue }
                    let p = Self.curve.value(at: local)
                    let angle = Double(i * 30 + 8) * .pi / 180
                    let distance = (34 + (150 - 34) * p) * scale
                    let radius = 3 * (1 - 0.7 * p) * scale
                    let x = center.x + cos(angle) * distance
                    let y = center.y + sin(angle) * distance
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Self.colors[i % 3].opacity(1 - p)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
