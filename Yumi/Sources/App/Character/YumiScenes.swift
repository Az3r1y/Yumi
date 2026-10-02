import SwiftUI

// The scenes of Contracts/EventAnimations.swift: something happened outside (a star, a fork,
// a merge) and Yumi plays it once, in two seconds at most, then goes back to what he was
// doing. Each scene is a few beats on the soft body (like a pose) plus what is drawn around
// him. They are made of large shapes so they still read on the folded island.

/// What a scene needs to be drawn at one instant.
struct YumiSceneMoment {
    var scene: YumiScene
    /// Seconds since the scene started.
    var t: CGFloat
    /// How many events it stands for, 1…4: a larger count amplifies the scene a little.
    var amount: Int
}

/// A second, smaller slime: the copy of a fork, the drop of a merge, the visitor of a follow.
/// Same outline as Yumi (`bodyPath`), so it wobbles and leans like him.
struct YumiTwin {
    var dx: CGFloat           // offset of its base from Yumi's, in units
    var dy: CGFloat = 0
    var scale: CGFloat
    var h: CGFloat = 1
    var lean: CGFloat = 0
    var alpha: CGFloat = 1
    /// Still part of Yumi's body: the two outlines are one.
    var attached = false
    /// Thickness of the strand of slime between the two, 0 when there is none.
    var strand: CGFloat = 0
    /// Angle of its waving arm in degrees, nil when the arm is in.
    var wave: CGFloat?
    var lookX: CGFloat = 0

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: 50 + dx, y: 76 + dy).scaledBy(x: scale, y: scale).translatedBy(x: -50, y: -76)
    }

    var path: Path {
        YumiRenderer.bodyPath(h: h, w: max(0.68, min(1.55, 1 / pow(h, 0.62))), lean: lean).applying(transform)
    }

    /// The strand of slime that still ties it to Yumi.
    var strandPath: Path? {
        guard strand > 0.5 else { return nil }
        var line = Path()
        line.move(to: CGPoint(x: 50 + (dx > 0 ? 18 : -18), y: 60))
        line.addLine(to: CGPoint(x: 50 + dx, y: 76 + dy - 30 * scale))
        return line.strokedPath(StrokeStyle(lineWidth: strand, lineCap: .round))
    }
}

extension YumiScene {
    /// Two seconds at most.
    var duration: Double {
        switch self {
        case .star:        return 1.8
        case .fork:        return 2.0
        case .pullRequest: return 1.8
        case .merge:       return 2.0
        case .push:        return 1.5
        case .commit:      return 1.6
        case .issue:       return 1.7
        case .release:     return 2.0
        case .follower:    return 2.0
        }
    }
}

private func seg(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { max(0, min(1, (t - a) / (b - a))) }

// MARK: - What the body does

extension YumiBlob {
    /// The beats of a scene, in milliseconds, like `steps(for:)` for a pose.
    static func steps(for scene: YumiScene, amount n: Int) -> [Step] {
        let more = CGFloat(n - 1)
        func look(_ x: CGFloat, _ y: CGFloat, _ base: YumiFace = .neutral) -> YumiFace {
            var f = base; f.look = CGPoint(x: x, y: y); return f
        }
        let back: (YumiBlob) -> Void = { $0.tempFace = nil }
        switch scene {
        case .star:
            // he watches it fall, catches it with a bounce, and beams
            return [
                Step(at: 0)    { b in b.tempFace = .skyward },
                Step(at: 600)  { b in b.h = 0.8 - 0.03 * more; b.vh = 0; b.c = 7; b.tempFace = .happy },
                Step(at: 1700, run: back),
            ]
        case .fork:
            // he gathers himself, a part of him pulls away to the right, the strand snaps
            return [
                Step(at: 0)    { b in b.hard(); b.th = 0.8; b.tempFace = .squeezed },
                Step(at: 250)  { b in b.k = 120; b.c = 8; b.th = 0.92; b.leanTarget = -7 },
                Step(at: 850)  { b in b.soft(); b.leanTarget = 0; b.th = 1; b.vh -= 2.5; b.fling(1); b.tempFace = .surprised },
                Step(at: 1050) { b in b.tempFace = look(1, 0.1) },
                Step(at: 1500) { b in b.tempFace = look(1, 0.1, .happy) },
                Step(at: 1900, run: back),
            ]
        case .merge:
            // a drop hops in from the right, he leans to it, they become one and he swells
            return [
                Step(at: 0)    { b in b.tempFace = look(1, 0.1, .curious) },
                Step(at: 750)  { b in b.leanTarget = 6 },
                Step(at: 1000) { b in b.soft(); b.c = 6; b.leanTarget = 0; b.th = 1.14 + 0.04 * more; b.splat(2 + n, 0.8); b.tempFace = .happy },
                Step(at: 1300) { b in b.th = 1 },
                Step(at: 1900, run: back),
            ]
        case .pullRequest:
            return [
                Step(at: 0)    { b in b.th = 1.07; b.tempFace = look(0.7, -0.6, .happy) },
                Step(at: 1450) { b in b.th = 1 },
                Step(at: 1750, run: back),
            ]
        case .push:
            // crouch, then throw
            return [
                Step(at: 0)    { b in b.hard(); b.th = 0.68; b.tempFace = .skyward },
                Step(at: 280)  { b in b.soft(); b.c = 7; b.th = 1.16 },
                Step(at: 520)  { b in b.th = 1 },
                Step(at: 1400, run: back),
            ]
        case .commit:
            return [
                Step(at: 250)  { b in b.tempFace = look(1, -0.1) },
                Step(at: 450)  { b in b.vh -= 2.4 },
                Step(at: 1400, run: back),
            ]
        case .issue:
            return [
                Step(at: 0)    { b in b.tempFace = .skyward },
                Step(at: 100)  { b in b.vh -= 2.4 },
                Step(at: 1500, run: back),
            ]
        case .release:
            // confetti, and a bow
            return [
                Step(at: 0)    { b in b.tempFace = .happy; b.vh -= 2.4 },
                Step(at: 550)  { b in b.hard(); b.th = 0.62; b.tempFace = .shut },
                Step(at: 1150) { b in b.soft(); b.th = 1; b.tempFace = .happy },
                Step(at: 1900, run: back),
            ]
        case .follower:
            return [
                Step(at: 300)  { b in b.tempFace = look(1, 0, .curious) },
                Step(at: 750)  { b in b.vh -= 2.4; b.tempFace = look(1, 0, .happy) },
                Step(at: 1900, run: back),
            ]
        }
    }
}

// MARK: - The other slimes

enum YumiScenes {

    /// The second slime of a scene at this instant, and a third one when several followers came.
    static func twins(_ m: YumiSceneMoment) -> [YumiTwin] {
        let t = m.t, more = CGFloat(m.amount - 1)
        // a wobble that dies out, for a body that has just been let go
        func wobble(since t0: CGFloat) -> CGFloat {
            t < t0 ? 1 : 1 + 0.14 * sin((t - t0) * 16) * exp(-(t - t0) * 4.5)
        }
        func waving(_ a: CGFloat, _ b: CGFloat) -> CGFloat? {
            t > a && t < b ? -20 + 26 * sin((t - a) * 14) : nil
        }
        switch m.scene {
        case .fork:
            let out = YumiCurve.easeInOut(seg(t, 0.25, 0.9))
            var twin = YumiTwin(dx: 60 * out + 46 * pow(seg(t, 1.5, 1.95), 2), scale: 0.25 + (0.38 + 0.05 * more) * out)
            twin.attached = t < 0.85
            twin.strand = twin.attached ? 30 * (1 - seg(t, 0.45, 0.85)) + 3 : 0
            twin.h = wobble(since: 0.85)
            twin.lean = 7 * sin(.pi * seg(t, 0.25, 0.9)) + 8 * seg(t, 1.5, 1.95)
            twin.wave = waving(1.0, 1.5)
            twin.lookX = t < 1.5 ? -1 : 1
            twin.alpha = 1 - seg(t, 1.7, 1.95)
            return t > 0.2 && t < 1.95 ? [twin] : []
        case .merge:
            let come = YumiCurve.easeInOut(seg(t, 0.15, 0.95))
            let eaten = seg(t, 0.95, 1.2)
            var twin = YumiTwin(dx: 62 * (1 - come), scale: (0.58 + 0.05 * more) * (1 - eaten))
            twin.dy = -9 * abs(sin(.pi * 3 * seg(t, 0.15, 0.8))) * (1 - come)
            twin.h = 1 + 0.1 * sin(.pi * 6 * seg(t, 0.15, 0.8)) * (1 - come)
            twin.lean = -6 * sin(.pi * seg(t, 0.15, 0.95))
            twin.attached = t > 0.78
            twin.strand = twin.attached ? 34 * seg(t, 0.78, 1.0) + 3 : 0
            twin.lookX = -1
            twin.alpha = seg(t, 0.15, 0.3)
            return t > 0.15 && t < 1.2 ? [twin] : []
        case .follower:
            func visitor(delay: CGFloat, dx: CGFloat, scale: CGFloat) -> YumiTwin {
                let u = t - delay
                var twin = YumiTwin(dx: dx + 24 * (1 - YumiCurve.easeOut(seg(u, 0.1, 0.5))) + 34 * pow(seg(u, 1.45, 1.85), 2), scale: scale)
                twin.lean = -7 + 5 * seg(u, 1.45, 1.85) * 3
                twin.h = 1 + 0.06 * sin(u * 9) * (1 - seg(u, 0.5, 1.2))
                twin.wave = u > 0.6 && u < 1.4 ? -20 + 26 * sin((u - 0.6) * 14) : nil
                twin.lookX = -1
                twin.alpha = seg(u, 0.1, 0.3) * (1 - seg(u, 1.6, 1.85))
                return twin
            }
            var all = [visitor(delay: 0, dx: 54, scale: 0.42)]
            if m.amount > 1 { all.insert(visitor(delay: 0.12, dx: 72, scale: 0.33), at: 0) }
            return all
        default:
            return []
        }
    }

    // MARK: Drawing

    private static let gold = Color(.sRGB, red: 1, green: 0.827, blue: 0.478)

    private static func star4(_ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4 - .pi / 2, k = i % 2 == 0 ? r : r * 0.32
            let pt = CGPoint(x: cos(a) * k, y: sin(a) * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private static func star5(_ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = CGFloat(i) * .pi / 5 - .pi / 2, k = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: cos(a) * k, y: sin(a) * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// A slime that stands on its own: arm, black body, rim, two plain eyes.
    static func draw(_ twin: YumiTwin, rim: GraphicsContext.Shading, rimWidth: CGFloat, in context: GraphicsContext) {
        guard twin.scale > 0.05, twin.alpha > 0.01 else { return }
        var c = context
        c.opacity = twin.alpha
        if !twin.attached {
            if let angle = twin.wave {
                // its arm, on the side it waves to
                let side: CGFloat = twin.lookX < 0 ? -1 : 1
                var arm = c
                arm.concatenate(twin.transform)
                arm.translateBy(x: 50 + side * 33, y: 52)
                arm.rotate(by: .degrees(Double(side * angle)))
                var line = Path()
                line.move(to: .zero)
                line.addLine(to: CGPoint(x: side * 14, y: -17))
                arm.stroke(line, with: rim, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                arm.stroke(line, with: .color(.black), style: StrokeStyle(lineWidth: 7.6, lineCap: .round))
            }
            let path = twin.path
            c.fill(path, with: .color(.black))
            c.stroke(path, with: rim, lineWidth: rimWidth)
        }
        // eyes: they are what makes it a slime, even at a few points
        var face = c
        face.concatenate(twin.transform)
        let top = 76 - 68 * twin.h
        for sd: CGFloat in [-1, 1] {
            let cx = 50 + sd * 14 + twin.lean * 0.5, cy = top + 37 * twin.h
            face.fill(Path(ellipseIn: CGRect(x: cx - 9.5, y: cy - 11.5, width: 19, height: 23)), with: .color(.white))
            face.fill(Path(ellipseIn: CGRect(x: cx - 5.4 + twin.lookX * 2.6, y: cy - 4.4, width: 10.8, height: 10.8)), with: .color(.black))
        }
    }

    /// Everything a scene draws around Yumi, except the slimes. `top` is the top of his head.
    static func drawExtras(_ m: YumiSceneMoment, rim: [YumiRGB], top: CGFloat, faceShift: CGPoint, in context: GraphicsContext) {
        let t = m.t, n = m.amount
        let mid = rim[1].color
        switch m.scene {

        case .star:
            // one star falls for each, a little apart; then his eyes sparkle
            for i in 0..<n {
                let p = seg(t - CGFloat(i) * 0.09, 0, 0.6)
                guard p > 0, p < 1 else { continue }
                let side: CGFloat = i == 0 ? 0 : (i % 2 == 0 ? 1 : -1) * CGFloat((i + 1) / 2) * 13
                var c = context
                c.translateBy(x: 50 + side * (1 - p), y: -48 + (top + 4 + 48) * p * p)
                c.rotate(by: .degrees(Double(300 * p)))
                c.fill(star5(i == 0 ? 9 : 6.5), with: .color(gold))
            }
            let glow = sin(.pi * seg(t, 0.62, 1.6))
            if glow > 0.02 {
                for cx: CGFloat in [37, 63] {
                    var c = context
                    c.translateBy(x: cx + faceShift.x + 2, y: 45 + faceShift.y - 2)
                    c.rotate(by: .degrees(Double(t * 120)))
                    c.fill(star4((5.5 + CGFloat(n - 1)) * glow), with: .color(gold))
                }
            }

        case .pullRequest:
            // a small branch held up at the end of his arm
            let k = YumiCurve.spring(seg(t, 0.2, 0.6)) * (1 - seg(t, 1.45, 1.75))
            guard k > 0.02 else { return }
            var c = context
            c.translateBy(x: 103, y: 22)
            c.scaleBy(x: 1.8 * k, y: 1.8 * k)
            c.opacity = min(1, k)
            var branch = Path()
            branch.move(to: CGPoint(x: 0, y: 10)); branch.addLine(to: CGPoint(x: 0, y: -10))
            branch.move(to: CGPoint(x: 0, y: 4))
            branch.addQuadCurve(to: CGPoint(x: 9, y: -6), control: CGPoint(x: 9, y: 4))
            var nodes = [CGPoint(x: 0, y: 10), CGPoint(x: 0, y: -10), CGPoint(x: 9, y: -6)]
            if n > 1 {
                branch.move(to: CGPoint(x: 0, y: 0))
                branch.addQuadCurve(to: CGPoint(x: -8, y: -9), control: CGPoint(x: -8, y: 0))
                nodes.append(CGPoint(x: -8, y: -9))
            }
            c.stroke(branch, with: .color(mid), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            for p in nodes {
                let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
                c.fill(dot, with: .color(.black))
                c.stroke(dot, with: .color(mid), lineWidth: 2.2)
            }

        case .push:
            // a drop thrown straight up, stretched by its speed
            for i in 0..<n {
                let p = seg(t - 0.28 - CGFloat(i) * 0.09, 0, 0.65)
                guard p > 0, p < 1 else { continue }
                let x = 50 + (i == 0 ? 0 : (i % 2 == 0 ? 1 : -1) * CGFloat((i + 1) / 2) * 8)
                let y = top - 4 - 78 * YumiCurve.easeOut(p)
                let r = (i == 0 ? 5 : 3.6) * (1 - 0.35 * p)
                var c = context
                c.opacity = 1 - seg(p, 0.7, 1)
                c.fill(Path(ellipseIn: CGRect(x: x - r * 0.8, y: y - r * 1.5, width: r * 1.6, height: r * 3)), with: .color(mid))
                c.fill(Path(ellipseIn: CGRect(x: x - r * 0.4, y: y + r * 2.2, width: r * 0.8, height: r * 0.8)), with: .color(mid))
            }

        case .commit:
            // a little line beside him, and a dot that adds itself to it
            let k = seg(t, 0, 0.2) * (1 - seg(t, 1.3, 1.6))
            guard k > 0.02 else { return }
            var c = context
            c.opacity = k
            let x: CGFloat = 113
            var line = Path()
            line.move(to: CGPoint(x: x, y: 68)); line.addLine(to: CGPoint(x: x, y: 24 - CGFloat(n - 1) * 5))
            c.stroke(line, with: .color(mid), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            for y: CGFloat in [62, 50] {
                let dot = Path(ellipseIn: CGRect(x: x - 3.4, y: y - 3.4, width: 6.8, height: 6.8))
                c.fill(dot, with: .color(.black))
                c.stroke(dot, with: .color(mid), lineWidth: 2)
            }
            for i in 0..<min(n, 3) {
                let s = YumiCurve.spring(seg(t, 0.45 + CGFloat(i) * 0.16, 0.75 + CGFloat(i) * 0.16))
                guard s > 0.02 else { continue }
                let r = 4.6 * s
                c.fill(Path(ellipseIn: CGRect(x: x - r, y: 38 - CGFloat(i) * 11 - r, width: r * 2, height: r * 2)), with: .color(mid))
            }

        case .issue:
            // a mark pops above his head
            let k = YumiCurve.spring(seg(t, 0.1, 0.45)) * (1 - seg(t, 1.35, 1.7))
            guard k > 0.02 else { return }
            var c = context
            c.translateBy(x: 50, y: top - 18)
            c.rotate(by: .degrees(Double(6 * sin(t * 9) * (1 - seg(t, 0.4, 1.2)))))
            let s = (1 + 0.14 * CGFloat(n - 1)) * k
            c.scaleBy(x: s, y: s)
            c.opacity = min(1, k)
            let ring = Path(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20))
            c.fill(ring, with: .color(.black))
            c.stroke(ring, with: .color(mid), lineWidth: 2.4)
            var mark = Path()
            mark.move(to: CGPoint(x: 0, y: -5.5)); mark.addLine(to: CGPoint(x: 0, y: 1.5))
            c.stroke(mark, with: .color(.white), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: -1.6, y: 4, width: 3.2, height: 3.2)), with: .color(.white))

        case .release:
            // confetti thrown from above his head; the positions only depend on the index
            let u = t - 0.1
            guard u > 0 else { return }
            let colours: [Color] = [rim[0].color, rim[1].color, rim[2].color, gold, Color(.sRGB, red: 0.239, green: 0.863, blue: 0.592)]
            let alpha = 1 - seg(t, 1.5, 1.95)
            for i in 0..<(14 + 6 * (n - 1)) {
                let f = CGFloat(i)
                let angle = -.pi / 2 + (fmod(f * 0.618, 1) - 0.5) * 2.4
                let speed = 70 + 55 * fmod(f * 0.377, 1)
                let x = 50 + cos(angle) * speed * u * (1 - 0.25 * u)
                let y = top + sin(angle) * speed * u + 95 * u * u
                var c = context
                c.opacity = alpha
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(Double(f + u * (4 + fmod(f, 3)))))
                c.fill(Path(CGRect(x: -2.4, y: -1.3, width: 4.8, height: 2.6)), with: .color(colours[i % colours.count]))
            }

        case .fork, .merge, .follower:
            break
        }
    }

    /// The arm he raises to hold the branch up: opacity, 0 when it is in.
    static func raisedArm(_ m: YumiSceneMoment) -> CGFloat {
        m.scene == .pullRequest ? seg(m.t, 0.1, 0.3) * (1 - seg(m.t, 1.5, 1.75)) : 0
    }
}
