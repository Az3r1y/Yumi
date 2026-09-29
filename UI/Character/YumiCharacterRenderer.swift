import SwiftUI
import CoreGraphics

/// Vector renderer for the Yumi slime — follows the official DA sheet:
/// a wide blue blob with a wavy top, pink/purple rim light on the edges,
/// two huge white eyes with big navy pupils (shine included), tiny mouth.
///
/// Pure function of (context, size, pose) — no state, no clocks.
enum YumiCharacterRenderer {

    // MARK: - Entry point

    static func draw(pose: CharacterPose, in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) * 0.5 * 0.72
        guard radius > 1 else { return }

        let detail = DetailLevel(radius: radius)
        let d = pose.deformation
        let cx = size.width / 2 + d.offsetX * radius
        // Bottom anchor: squash and stretch pivot around the ground line.
        let groundY = size.height / 2 + radius * 1.02
        let cy = groundY - radius * 0.95 + d.offsetY * radius

        var body = context
        body.translateBy(x: cx, y: cy)
        body.rotate(by: .radians(d.lean))
        body.scaleBy(x: d.scaleX, y: d.scaleY)
        // Compensate the bottom anchor under vertical scale.
        body.translateBy(x: 0, y: radius * (1 - d.scaleY))

        let bodyPath = slimePath(radius: radius)

        // ── Rim lights (DA signature): offset copies of the body drawn
        // behind it, peeking out — pink lower-left, purple upper-right.
        if detail.rim {
            var pink = context
            pink.translateBy(x: -radius * 0.06, y: radius * 0.05)
            pink.fill(bodyPath, with: .color(CharacterColors.rimPink))
            var purple = context
            purple.translateBy(x: radius * 0.055, y: -radius * 0.05)
            purple.fill(bodyPath, with: .color(CharacterColors.rimPurple))
        }

        // ── Body ──
        body.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [CharacterColors.bodyTop, CharacterColors.bodyBottom]),
            startPoint: CGPoint(x: 0, y: -radius * 0.85),
            endPoint: CGPoint(x: 0, y: radius * 0.95)))

        // Subtle bottom shading (volume cue).
        body.fill(bodyPath, with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.black.opacity(0.14), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: -radius * 0.2),
            endPoint: CGPoint(x: 0, y: radius)))

        // Glossy highlight — a clean band upper-left plus a small sparkle.
        if detail.gloss {
            let gloss = ellipsePath(cx: -radius * 0.34, cy: -radius * 0.44,
                                    rx: radius * 0.24, ry: radius * 0.085,
                                    rotation: -0.32)
            body.fill(gloss, with: .color(Color.white.opacity(0.42)))
        }

        // ── Face ──
        drawFace(pose: pose, radius: radius, detail: detail, in: &body)
    }

    // MARK: - Face

    private static func drawFace(pose: CharacterPose, radius: CGFloat,
                                 detail: DetailLevel, in context: inout GraphicsContext) {
        let f = pose.face
        let ink = CharacterColors.ink

        // Eyes resist the body squash: counter-scale the face so it stays
        // readable while the body deforms (resistance 1 = face undeformed).
        let d = pose.deformation
        let r = d.eyeSquashResistance
        let counterX = d.scaleX == 0 ? 1 : (1 + (d.scaleX - 1) * r) / d.scaleX
        let counterY = d.scaleY == 0 ? 1 : (1 + (d.scaleY - 1) * r) / d.scaleY
        context.scaleBy(x: counterX, y: counterY)

        // Huge white eyes, well separated — the DA's main signature.
        let spacing = radius * 0.44 * f.eyeSpacing
        let eyeY = -radius * 0.18 * f.eyeHeight
        let eyeW = radius * 0.30 * f.eyeScale
        let eyeH = radius * 0.36 * f.eyeScale * f.eyeOpenness
        let pupil = CGSize(width: f.pupilOffset.width * radius * 0.5,
                           height: f.pupilOffset.height * radius * 0.5)

        for side in [-1.0, 1.0] {
            let ex = CGFloat(side) * spacing + pupil.width
            let ey = eyeY + pupil.height

            // Sclera: big white oval.
            let eyeRect = CGRect(x: ex - eyeW / 2, y: ey - eyeH / 2,
                                 width: eyeW, height: max(eyeH, eyeW * 0.35))
            context.fill(Path(ellipseIn: eyeRect), with: .color(.white))

            // Pupil: huge navy oval, sits center-low (the DA look).
            if detail.pupils && f.eyeOpenness > 0.22 {
                let pw = eyeW * 0.62
                let ph = min(eyeH * 0.85, pw * 1.05)
                let pupilRect = CGRect(x: ex - pw / 2, y: ey - ph / 2 + eyeH * 0.08,
                                       width: pw, height: ph)
                context.fill(Path(ellipseIn: pupilRect), with: .color(ink))

                // Big white shine upper-left of the pupil (DA signature).
                if detail.shine {
                    let shineRect = CGRect(x: ex - pw * 0.34, y: ey - ph * 0.38,
                                           width: pw * 0.38, height: pw * 0.34)
                    context.fill(Path(ellipseIn: shineRect), with: .color(.white))
                    // Tiny secondary sparkle.
                    let sparkRect = CGRect(x: ex + pw * 0.10, y: ey + ph * 0.06,
                                           width: pw * 0.16, height: pw * 0.14)
                    context.fill(Path(ellipseIn: sparkRect), with: .color(.white.opacity(0.85)))
                }
            }
        }

        // Brows — short ink strokes above the eyes (subtle on the DA model).
        if detail.brows {
            let browY = eyeY - radius * 0.22 * f.browHeight
            let browLength = radius * 0.14
            for side in [-1.0, 1.0] {
                let bx = CGFloat(side) * spacing * 0.94
                var brow = Path()
                let inner = CGPoint(x: bx - CGFloat(side) * browLength * 0.5,
                                    y: browY - CGFloat(side) * sin(f.browAngle) * browLength * 0.5)
                let outer = CGPoint(x: bx + CGFloat(side) * browLength * 0.5,
                                    y: browY + CGFloat(side) * sin(f.browAngle) * browLength * 0.5)
                brow.move(to: inner)
                brow.addLine(to: outer)
                context.stroke(brow, with: .color(ink.opacity(0.85)),
                               style: StrokeStyle(lineWidth: max(1, radius * 0.045), lineCap: .round))
            }
        }

        // Mouth — small, below and between the eyes.
        let mouthY = radius * 0.30
        let mw = radius * 0.18 * f.mouthScale
        var mouth = Path()
        switch f.mouth {
        case .neutral:
            mouth.move(to: CGPoint(x: -mw / 2, y: mouthY))
            mouth.addLine(to: CGPoint(x: mw / 2, y: mouthY))
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        case .flat:
            mouth.move(to: CGPoint(x: -mw * 0.8, y: mouthY))
            mouth.addLine(to: CGPoint(x: mw * 0.8, y: mouthY))
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        case .smallOpen:
            let mh = mw * 0.55
            context.fill(Path(ellipseIn: CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)),
                         with: .color(ink))
        case .wideOpen:
            let mh = mw * 0.95
            context.fill(Path(ellipseIn: CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)),
                         with: .color(ink))
        case .wavy:
            let seg = mw / 4
            mouth.move(to: CGPoint(x: -mw / 2, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: -mw / 2 + seg * 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg, y: mouthY - mw * 0.24))
            mouth.addQuadCurve(to: CGPoint(x: mw / 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg * 3, y: mouthY + mw * 0.24))
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.045), lineCap: .round))
        case .smile:
            mouth.addArc(center: CGPoint(x: 0, y: mouthY - mw * 0.30),
                         radius: mw * 0.66,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        }
    }

    // MARK: - Body path

    /// The Yumi silhouette per the DA: a wide, low blob whose top edge undulates
    /// gently (two soft bumps) — closed Catmull-Rom spline, radius multiples,
    /// y-down, origin at body center.
    static func slimePath(radius: CGFloat) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (-0.74,  0.46),   // bottom-left
            (-0.90,  0.02),   // left bulge (full)
            (-0.72, -0.38),   // left shoulder
            (-0.38, -0.58),   // wave crest left
            (-0.05, -0.66),   // wave trough (center dips slightly)
            ( 0.30, -0.62),   // wave crest right (higher — the DA's lopsided top)
            ( 0.66, -0.40),   // right shoulder
            ( 0.88,  0.04),   // right bulge
            ( 0.70,  0.48),   // bottom-right
            ( 0.00,  0.68),   // bottom (resting weight)
        ]
        return closedSpline(points.map { CGPoint(x: $0.0 * radius, y: $0.1 * radius) })
    }

    /// Closed Catmull-Rom spline converted to cubic Béziers — smooth organic
    /// outlines without corner artifacts.
    static func closedSpline(_ pts: [CGPoint]) -> Path {
        let n = pts.count
        guard n >= 3 else { return Path() }
        var p = Path()
        p.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n]
            let p1 = pts[i]
            let p2 = pts[(i + 1) % n]
            let p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        p.closeSubpath()
        return p
    }

    // MARK: - Small helpers

    private static func ellipsePath(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat,
                                    rotation: CGFloat) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
        return path.applying(t)
    }

    // MARK: - Detail levels (scale adaptivity)

    /// Which details to draw at which size — readable at 16 px, richer at 128 px.
    struct DetailLevel {
        var radius: CGFloat

        var large: Bool { radius >= 32 }
        var rim: Bool { radius >= 12 }
        var gloss: Bool { radius >= 14 }
        var shine: Bool { radius >= 20 }
        var pupils: Bool { radius >= 8 }
        var brows: Bool { radius >= 10 }
    }
}
