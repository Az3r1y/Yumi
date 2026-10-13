import SwiftUI

/// What Yumi wears (`SKINS` of the island demo, and a few more), in the 100 × 84 box of the
/// mock-up. The head ones are drawn in the space of `drawTops`, so they ride the top of the
/// body; the face ones in the space of `drawProps`, so they follow the face. Each one lives a
/// little on its own (a pompom that bounces, a glint, an ear that twitches), and what sticks
/// out lags behind when he leans. They sit with his habits and scenes.
enum YumiCostumes {

    /// What a costume needs to move: the clock, the lean of the top of the body, the island colour.
    struct Moment {
        var time: CGFloat
        var lean: CGFloat
        var accent: Color
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private static let white = rgb(0xF4F5F8)

    private static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    /// A four-pointed sparkle.
    private static func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        let k = r * 0.26
        return polygon([CGPoint(x: cx, y: cy - r), CGPoint(x: cx + k, y: cy - k), CGPoint(x: cx + r, y: cy),
                        CGPoint(x: cx + k, y: cy + k), CGPoint(x: cx, y: cy + r), CGPoint(x: cx - k, y: cy + k),
                        CGPoint(x: cx - r, y: cy), CGPoint(x: cx - k, y: cy - k)])
    }

    /// 0 most of the time, a quick 0 → 1 → 0 once every `period` seconds, lasting `length`.
    private static func flick(_ t: CGFloat, period: CGFloat, length: CGFloat, offset: CGFloat = 0) -> CGFloat {
        let p = (t + offset).truncatingRemainder(dividingBy: period)
        guard p < length else { return 0 }
        return sin(.pi * p / length)
    }

    /// A bright band sweeping across `shape` once every `period` seconds.
    private static func glint(_ shape: Path, in c: GraphicsContext, t: CGFloat, period: CGFloat, offset: CGFloat = 0, alpha: Double = 0.85) {
        let p = (t + offset).truncatingRemainder(dividingBy: period) / 0.6
        guard p < 1 else { return }
        let box = shape.boundingRect
        var g = c
        g.clip(to: shape)
        let x = box.minX - 8 + (box.width + 16) * p
        g.stroke(line(CGPoint(x: x - 4, y: box.maxY + 2), CGPoint(x: x + 4, y: box.minY - 2)),
                 with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }

    // MARK: - Head

    static func drawHead(_ costume: YumiCostume, _ m: Moment, in c: GraphicsContext) {
        let t = m.time
        // What sticks out lags behind the lean, then catches up
        let lag = -m.lean * 0.22
        switch costume {
        case .beanie:
            var dome = Path()
            dome.move(to: CGPoint(x: 17, y: 24))
            dome.addQuadCurve(to: CGPoint(x: 83, y: 24), control: CGPoint(x: 50 + lag * 0.4, y: -16))
            dome.closeSubpath()
            c.fill(dome, with: .color(m.accent))
            let band = CGRect(x: 14, y: 17, width: 72, height: 10)
            c.fill(Path(roundedRect: band, cornerRadius: 5), with: .color(white))
            var ribs = c
            ribs.clip(to: Path(roundedRect: band, cornerRadius: 5))
            for x in stride(from: CGFloat(19), through: 82, by: 5) {
                ribs.stroke(line(CGPoint(x: x, y: 17), CGPoint(x: x, y: 27)), with: .color(rgb(0xC9CCD8)), lineWidth: 1)
            }
            // The pompom bounces on its own and swings when he leans
            let bounce = abs(sin(t * 3.2)) * 2.2
            c.fill(circle(50 + lag, -6 - bounce, 6.5), with: .color(white))
            c.fill(circle(48 + lag, -8 - bounce, 2.2), with: .color(.white))

        case .crown:
            let crown = polygon([CGPoint(x: 27, y: 14), CGPoint(x: 31, y: -7), CGPoint(x: 41, y: 5), CGPoint(x: 50, y: -11),
                                 CGPoint(x: 59, y: 5), CGPoint(x: 69, y: -7), CGPoint(x: 73, y: 14)])
            c.fill(crown, with: .linearGradient(Gradient(colors: [rgb(0xFFE27A), rgb(0xFFC21A)]),
                                                startPoint: CGPoint(x: 50, y: -11), endPoint: CGPoint(x: 50, y: 14)))
            c.stroke(crown, with: .color(rgb(0xE0A800)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            glint(crown, in: c, t: t, period: 3.4)
            c.fill(circle(50, 6, 2.6), with: .color(rgb(0xFF5D8F)))
            c.fill(circle(36, 9, 1.8), with: .color(rgb(0x5B8CFF)))
            c.fill(circle(64, 9, 1.8), with: .color(rgb(0x5B8CFF)))
            // The points twinkle in turn
            for (i, tip) in [CGPoint(x: 31, y: -7), CGPoint(x: 50, y: -11), CGPoint(x: 69, y: -7)].enumerated() {
                let k = flick(t, period: 2.4, length: 0.5, offset: CGFloat(i) * 0.8)
                if k > 0.01 { c.fill(star(tip.x, tip.y - 3, 4 * k), with: .color(.white)) }
            }

        case .cat:
            let ears: [(base: CGPoint, points: [CGPoint], inner: [CGPoint], offset: CGFloat)] = [
                (CGPoint(x: 28, y: 19), [CGPoint(x: 16, y: 26), CGPoint(x: 20, y: -4), CGPoint(x: 40, y: 12)],
                 [CGPoint(x: 22, y: 18), CGPoint(x: 23, y: 4), CGPoint(x: 33, y: 12)], 0),
                (CGPoint(x: 72, y: 19), [CGPoint(x: 84, y: 26), CGPoint(x: 80, y: -4), CGPoint(x: 60, y: 12)],
                 [CGPoint(x: 78, y: 18), CGPoint(x: 77, y: 4), CGPoint(x: 67, y: 12)], 1.9),
            ]
            for (i, ear) in ears.enumerated() {
                // Now and then an ear twitches
                let side: CGFloat = i == 0 ? -1 : 1
                let twitch = flick(t, period: 4.3, length: 0.28, offset: ear.offset) * 14 * side + lag * 0.6
                var e = c
                e.translateBy(x: ear.base.x, y: ear.base.y)
                e.rotate(by: .degrees(Double(twitch)))
                e.translateBy(x: -ear.base.x, y: -ear.base.y)
                let path = polygon(ear.points)
                e.fill(path, with: .color(.black))
                e.stroke(path, with: .color(m.accent), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                e.fill(polygon(ear.inner), with: .color(rgb(0xFF8FC8)))
            }

        case .witch:
            c.fill(Path(ellipseIn: CGRect(x: 14, y: 8, width: 72, height: 12)), with: .color(rgb(0x2B2140)))
            // The cone sways and its tip curls the other way
            let sway = sin(t * 1.4) * 3 + lag
            let tip = CGPoint(x: 60 + sway, y: -30)
            c.fill(polygon([CGPoint(x: 31, y: 14), tip, CGPoint(x: 69, y: 14)]), with: .color(rgb(0x3A2B5C)))
            c.stroke(line(CGPoint(x: 33, y: 9), CGPoint(x: 67, y: 9)), with: .color(m.accent), lineWidth: 4)
            var curl = Path()
            curl.move(to: tip)
            curl.addQuadCurve(to: CGPoint(x: tip.x + 9 + sway * 0.4, y: -20), control: CGPoint(x: tip.x + 8, y: -28))
            c.stroke(curl, with: .color(rgb(0x3A2B5C)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            let k = flick(t, period: 2.8, length: 0.7)
            if k > 0.01 { c.fill(star(tip.x + 13, -24, 3.5 * k), with: .color(rgb(0xFFE27A))) }

        case .halo:
            // It floats, and its light breathes
            let lift = sin(t * 2) * 1.6
            let ring = Path(ellipseIn: CGRect(x: 28 + lag * 0.5, y: -13.5 + lift, width: 44, height: 11))
            var glow = c
            glow.opacity = 0.18 + 0.14 * Double((sin(t * 2.6) + 1) / 2)
            glow.stroke(ring, with: .color(rgb(0xFFE27A)), lineWidth: 8)
            c.stroke(ring, with: .color(rgb(0xFFE27A)), lineWidth: 3.2)

        case .flower:
            var flower = c
            flower.translateBy(x: 70 + lag * 0.5, y: 8 + sin(t * 1.8) * 0.8)
            flower.rotate(by: .degrees(Double(t * 18)))
            for angle in stride(from: 0.0, to: 360.0, by: 72.0) {
                var petal = flower
                petal.rotate(by: .degrees(angle))
                petal.fill(Path(ellipseIn: CGRect(x: -4.2, y: -12, width: 8.4, height: 12)), with: .color(rgb(0xFF9AC8)))
            }
            flower.fill(circle(0, 0, 3.6), with: .color(rgb(0xFFD24A)))

        case .party:
            let tip = CGPoint(x: 60 + lag, y: -26)
            let cone = polygon([CGPoint(x: 36, y: 13), tip, CGPoint(x: 66, y: 9)])
            c.fill(cone, with: .color(m.accent))
            var stripes = c
            stripes.clip(to: cone)
            for y in stride(from: CGFloat(-20), through: 12, by: 9) {
                stripes.stroke(line(CGPoint(x: 30, y: y + 8), CGPoint(x: 72, y: y)), with: .color(.white.opacity(0.85)), lineWidth: 2.6)
            }
            let bounce = abs(sin(t * 3.6)) * 1.8
            c.fill(circle(tip.x, tip.y - 2 - bounce, 4.2), with: .color(rgb(0xFFD24A)))
            // Confetti falling round the head, each on its own loop
            let colours: [UInt32] = [0xFF6FB5, 0x64D2FF, 0xFFD24A, 0x30D158, 0x8B6CFF]
            for i in 0..<7 {
                let p = (t / 2.4 + CGFloat(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let x = 12 + CGFloat((i * 37) % 76) + sin(t * 2 + CGFloat(i)) * 3
                var bit = c
                bit.opacity = Double(sin(.pi * p))
                bit.translateBy(x: x, y: -30 + p * 46)
                bit.rotate(by: .degrees(Double(t * 200 + CGFloat(i) * 40)))
                bit.fill(Path(CGRect(x: -1.4, y: -0.8, width: 2.8, height: 1.6)), with: .color(rgb(colours[i % colours.count])))
            }

        case .unicorn:
            let horn = polygon([CGPoint(x: 42, y: 13), CGPoint(x: 50 + lag * 0.6, y: -32), CGPoint(x: 58, y: 13)])
            // A rainbow that runs up the horn
            let shift = (t * 0.35).truncatingRemainder(dividingBy: 1)
            let hues: [Color] = [rgb(0xFF6FB5), rgb(0xFFD24A), rgb(0x30D158), rgb(0x64D2FF), rgb(0x8B6CFF), rgb(0xFF6FB5)]
            c.fill(horn, with: .linearGradient(Gradient(colors: hues), startPoint: CGPoint(x: 50, y: 12 + 38 * shift),
                                               endPoint: CGPoint(x: 50, y: -26 - 38 * (1 - shift))))
            var spiral = c
            spiral.clip(to: horn)
            for y in stride(from: CGFloat(-20), through: 10, by: 7) {
                spiral.stroke(line(CGPoint(x: 40, y: y + 4), CGPoint(x: 60, y: y)), with: .color(.white.opacity(0.55)), lineWidth: 1.4)
            }
            for (i, s) in [CGPoint(x: 38, y: -18), CGPoint(x: 62, y: -12), CGPoint(x: 56, y: -30)].enumerated() {
                let k = flick(t, period: 1.9, length: 0.6, offset: CGFloat(i) * 0.63)
                if k > 0.01 { c.fill(star(s.x + lag * 0.6, s.y, 3.8 * k), with: .color(.white)) }
            }

        case .antennae:
            for sd: CGFloat in [-1, 1] {
                let base = CGPoint(x: 50 + sd * 14, y: 12)
                let tip = CGPoint(x: 50 + sd * 22 + lag * 1.2 + sin(t * 2.2 + sd) * 2,
                                  y: -18 + sin(t * 3 + sd * 1.3) * 1.6)
                var stem = Path()
                stem.move(to: base)
                stem.addQuadCurve(to: tip, control: CGPoint(x: 50 + sd * 12, y: -4))
                c.stroke(stem, with: .color(m.accent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                var glow = c
                glow.opacity = 0.2 + 0.2 * Double((sin(t * 3.4 + sd) + 1) / 2)
                glow.fill(circle(tip.x, tip.y, 8), with: .color(m.accent))
                c.fill(circle(tip.x, tip.y, 4.2), with: .color(m.accent))
                c.fill(circle(tip.x - 1.3, tip.y - 1.3, 1.3), with: .color(.white))
            }

        case .bow:
            var bow = c
            bow.translateBy(x: 72 + lag * 0.4, y: 10)
            bow.rotate(by: .degrees(Double(14 + sin(t * 2.2) * 6)))
            let pink = GraphicsContext.Shading.color(rgb(0xFF6FB5))
            for sd: CGFloat in [-1, 1] {
                var loop = bow
                loop.rotate(by: .degrees(Double(sd * 18)))
                loop.fill(Path(ellipseIn: CGRect(x: sd < 0 ? -15 : 1, y: -5.5, width: 14, height: 11)), with: pink)
                loop.fill(Path(ellipseIn: CGRect(x: sd < 0 ? -11 : 4, y: -2.5, width: 6, height: 5)), with: .color(rgb(0xC9407F)))
            }
            bow.fill(Path(roundedRect: CGRect(x: -3.2, y: -3.6, width: 6.4, height: 7.2), cornerRadius: 2.4), with: .color(rgb(0xE5508F)))

        case .pirate:
            var scarf = Path()
            scarf.move(to: CGPoint(x: 14, y: 24))
            scarf.addQuadCurve(to: CGPoint(x: 86, y: 22), control: CGPoint(x: 50, y: -10))
            scarf.closeSubpath()
            c.fill(scarf, with: .color(rgb(0xE5484D)))
            var dots = c
            dots.clip(to: scarf)
            for p in [CGPoint(x: 32, y: 12), CGPoint(x: 48, y: 6), CGPoint(x: 64, y: 9), CGPoint(x: 40, y: 18), CGPoint(x: 58, y: 18)] {
                dots.fill(circle(p.x, p.y, 1.8), with: .color(white))
            }
            // The knot's tails flutter
            for (i, len) in [CGFloat(14), 11].enumerated() {
                var tail = c
                tail.translateBy(x: 85, y: 20)
                tail.rotate(by: .degrees(Double(20 + CGFloat(i) * 22 + sin(t * 5 + CGFloat(i)) * 9 - lag * 2)))
                tail.fill(polygon([CGPoint(x: 0, y: -2.5), CGPoint(x: len, y: 0), CGPoint(x: 0, y: 2.5)]), with: .color(rgb(0xC93A3F)))
            }
            c.fill(circle(85, 20, 3), with: .color(rgb(0xC93A3F)))

        case .none, .glasses, .mustache:
            break
        }
    }

    // MARK: - Face

    /// On the face. The eyes sit on a sphere and slide when the head turns (`drawFace`):
    /// what is worn on the face slides with them.
    static func drawFace(_ costume: YumiCostume, _ m: Moment, yaw: CGFloat, pitch: CGFloat, eyesScale: CGFloat,
                         in context: GraphicsContext) {
        let t = m.time
        var c = context
        // The middle of the face moves as the middle of the eyes does
        c.translateBy(x: sin(yaw) * cos(pitch) * 40.1 * 0.94, y: sin(pitch) * 30)
        c.translateBy(x: 50, y: 45)
        c.scaleBy(x: max(0.6, cos(yaw)), y: max(0.6, cos(pitch)))
        c.translateBy(x: -50, y: -45)

        /// The context of one eye, exactly where `drawFace` puts it.
        func eye(_ sd: CGFloat) -> GraphicsContext {
            let ya = sd * 0.33 + yaw
            var e = context
            e.translateBy(x: 50, y: 45)
            e.scaleBy(x: eyesScale, y: eyesScale)
            e.translateBy(x: -50, y: -45)
            e.translateBy(x: 50 + sin(ya) * cos(pitch) * 40.1, y: 45 + sin(pitch) * 30)
            e.scaleBy(x: max(0.35, cos(ya)), y: max(0.6, cos(pitch)))
            return e
        }

        switch costume {
        case .cat:
            var w = c
            w.opacity = 0.7
            let wiggle = sin(t * 2.6) * 1.2
            var whiskers = Path()
            for (a, b) in [((22, 58), (10, 58)), ((23, 62), (12, 65)), ((78, 58), (90, 58)), ((77, 62), (88, 65))] {
                whiskers.move(to: CGPoint(x: a.0, y: a.1))
                whiskers.addLine(to: CGPoint(x: CGFloat(b.0), y: CGFloat(b.1) + wiggle))
            }
            w.stroke(whiskers, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        case .glasses:
            let style = StrokeStyle(lineWidth: 2.2)
            for (i, sd) in [CGFloat(-1), 1].enumerated() {
                let lens = eye(sd)
                lens.stroke(circle(0, 0, 12), with: .color(white), style: style)
                glint(circle(0, 0, 11), in: lens, t: t, period: 4.2, offset: CGFloat(i) * 0.12, alpha: 0.6)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: 49, y: 44))
            bridge.addQuadCurve(to: CGPoint(x: 51, y: 44), control: CGPoint(x: 50, y: 42))
            c.stroke(bridge, with: .color(white), style: style)

        case .mustache:
            // The tips twitch now and then
            var m = c
            let twitch = 1 + 0.08 * flick(t, period: 3.1, length: 0.35)
            m.translateBy(x: 50, y: 60)
            m.scaleBy(x: twitch, y: 1 / twitch)
            m.translateBy(x: -50, y: -60)
            var p = Path()
            p.move(to: CGPoint(x: 50, y: 60))
            p.addCurve(to: CGPoint(x: 33, y: 59), control1: CGPoint(x: 46, y: 56), control2: CGPoint(x: 38, y: 55))
            p.addCurve(to: CGPoint(x: 42, y: 63), control1: CGPoint(x: 37, y: 59), control2: CGPoint(x: 40, y: 62))
            p.addCurve(to: CGPoint(x: 50, y: 60), control1: CGPoint(x: 45, y: 64), control2: CGPoint(x: 48, y: 63))
            p.addCurve(to: CGPoint(x: 58, y: 63), control1: CGPoint(x: 52, y: 63), control2: CGPoint(x: 55, y: 64))
            p.addCurve(to: CGPoint(x: 67, y: 59), control1: CGPoint(x: 60, y: 62), control2: CGPoint(x: 63, y: 59))
            p.addCurve(to: CGPoint(x: 50, y: 60), control1: CGPoint(x: 62, y: 55), control2: CGPoint(x: 54, y: 56))
            p.closeSubpath()
            m.fill(p, with: .color(white))

        case .pirate:
            // The patch on his left eye, and its strap
            c.stroke(line(CGPoint(x: 12, y: 30), CGPoint(x: 88, y: 38)), with: .color(rgb(0x1A1A1F)), lineWidth: 2.2)
            let patch = eye(-1)
            patch.fill(Path(ellipseIn: CGRect(x: -11, y: -12, width: 22, height: 24)), with: .color(rgb(0x1A1A1F)))
            patch.stroke(Path(ellipseIn: CGRect(x: -11, y: -12, width: 22, height: 24)), with: .color(rgb(0x3A3A42)), lineWidth: 1.2)

        default:
            break
        }
    }
}
