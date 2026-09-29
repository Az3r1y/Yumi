import SwiftUI
import CoreGraphics

/// Vector renderer for the Yumi slime. Draws a pose (body deformation +
/// parametric face) into a SwiftUI Canvas context. Pure function of
/// (context, size, pose) — no state, no clocks.
///
/// Organic silhouette: a teardrop-like closed spline, deliberately a little
/// asymmetric so the blob feels soft and hand-made rather than geometric.
/// Deformation (squash/stretch/lean/hop) is applied through affine transforms
/// with bottom-anchoring so squashes flatten toward the ground.
enum YumiCharacterRenderer {

    // MARK: - Entry point

    static func draw(pose: CharacterPose, in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) * 0.5 * 0.72
        guard radius > 1 else { return }

        let detail = DetailLevel(radius: radius)
        let d = pose.deformation
        let cx = size.width / 2 + d.offsetX * radius
        // Bottom anchor: squash and stretch pivot around the ground line.
        let groundY = size.height / 2 + radius * 1.05
        let cy = groundY - radius + d.offsetY * radius

        var body = context
        body.translateBy(x: cx, y: cy)
        body.rotate(by: .radians(d.lean))
        body.scaleBy(x: d.scaleX, y: d.scaleY)
        // Compensate the bottom anchor under vertical scale.
        body.translateBy(x: 0, y: radius * (1 - d.scaleY))

        let bodyPath = slimePath(radius: radius)

        // ── Body ──
        body.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [CharacterColors.bodyTop, CharacterColors.bodyBottom]),
            startPoint: CGPoint(x: 0, y: -radius * 0.9),
            endPoint: CGPoint(x: 0, y: radius * 0.9)))

        // Subtle bottom shading (volume cue, cheap at small sizes).
        body.fill(bodyPath, with: .linearGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color.black.opacity(0.10), location: 1),
            ]),
            startPoint: CGPoint(x: 0, y: -radius * 0.3),
            endPoint: CGPoint(x: 0, y: radius)))

        // Glossy highlight (organic blob, offset top-left).
        if detail.gloss {
            let gloss = ellipsePath(cx: -radius * 0.30, cy: -radius * 0.42,
                                    rx: radius * 0.30, ry: radius * 0.16,
                                    rotation: -0.45)
            body.fill(gloss, with: .color(Color.white.opacity(0.35)))
        }

        // Tiny drips on the right — the "slightly weird" identity cue.
        if detail.drips {
            drawDrip(body: &body, radius: radius,
                     x: radius * 0.72, y: radius * 0.28, length: radius * 0.30, width: radius * 0.10)
            if detail.large {
                drawDrip(body: &body, radius: radius,
                         x: radius * 0.84, y: radius * -0.02, length: radius * 0.18, width: radius * 0.07)
            }
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

        let spacing = radius * 0.30 * f.eyeSpacing
        let eyeH = radius * 0.22 * f.eyeScale * f.eyeOpenness
        let eyeW = radius * 0.15 * f.eyeScale
        let eyeY = -radius * 0.12 * f.eyeHeight
        let pupil = CGSize(width: f.pupilOffset.width * radius * 0.5,
                           height: f.pupilOffset.height * radius * 0.5)

        for side in [-1.0, 1.0] {
            let ex = CGFloat(side) * spacing + pupil.width
            let ey = eyeY + pupil.height

            // Sclera
            let eyeRect = CGRect(x: ex - eyeW / 2, y: ey - eyeH / 2,
                                 width: eyeW, height: eyeH)
            let eye = Path(ellipseIn: eyeRect)
            context.fill(eye, with: .color(.white))

            // Pupil
            if detail.pupils && f.eyeOpenness > 0.25 {
                let pw = eyeW * 0.42
                let ph = max(eyeH * 0.55, pw * 0.8)
                let pupilRect = CGRect(x: ex - pw / 2, y: ey - ph / 2 + eyeH * 0.08,
                                       width: pw, height: ph)
                context.fill(Path(ellipseIn: pupilRect), with: .color(ink))
            }
        }

        // Brows — short ink strokes; the main secondary expression channel.
        if detail.brows {
            let browY = eyeY - radius * 0.20 * f.browHeight
            let browLength = radius * 0.14
            for side in [-1.0, 1.0] {
                let bx = CGFloat(side) * spacing * 0.9
                var brow = Path()
                let inner = CGPoint(x: bx - CGFloat(side) * browLength * 0.5,
                                    y: browY - CGFloat(side) * sin(f.browAngle) * browLength * 0.5)
                let outer = CGPoint(x: bx + CGFloat(side) * browLength * 0.5,
                                    y: browY + CGFloat(side) * sin(f.browAngle) * browLength * 0.5)
                brow.move(to: inner)
                brow.addLine(to: outer)
                context.stroke(brow, with: .color(ink),
                               style: StrokeStyle(lineWidth: max(1, radius * 0.045), lineCap: .round))
            }
        }

        // Mouth — small, below and between the eyes.
        let mouthY = radius * 0.20
        let mw = radius * 0.16 * f.mouthScale
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
            let mh = mw * 0.9
            context.fill(Path(ellipseIn: CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)),
                         with: .color(ink))
        case .wavy:
            let seg = mw / 4
            mouth.move(to: CGPoint(x: -mw / 2, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: -mw / 2 + seg * 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg, y: mouthY - mw * 0.22))
            mouth.addQuadCurve(to: CGPoint(x: mw / 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg * 3, y: mouthY + mw * 0.22))
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.045), lineCap: .round))
        case .smile:
            mouth.addArc(center: CGPoint(x: 0, y: mouthY - mw * 0.28),
                         radius: mw * 0.62,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            context.stroke(mouth, with: .color(ink),
                           style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        }
    }

    // MARK: - Body path

    /// The Yumi silhouette: a low, wide teardrop built from a closed Catmull-Rom
    /// spline over hand-placed control points (radii multiples). Slightly
    /// asymmetric: the right shoulder sits a touch higher, the left bulge is
    /// fuller — organic, not geometric.
    static func slimePath(radius: CGFloat) -> Path {
        // Control points (x, y) in radius units, y-down, origin at body center.
        let points: [(CGFloat, CGFloat)] = [
            (-0.86,  0.10),   // left bulge (full)
            (-0.74, -0.34),   // left shoulder
            (-0.30, -0.72),   // top-left slope
            ( 0.10, -0.78),   // top peak (slightly off-center)
            ( 0.52, -0.62),   // right shoulder (higher than left)
            ( 0.84, -0.10),   // right bulge
            ( 0.78,  0.42),   // right bottom
            ( 0.34,  0.72),   // bottom-right
            (-0.16,  0.76),   // bottom (resting weight, slightly left)
            (-0.66,  0.52),   // bottom-left
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

    private static func drawDrip(body: inout GraphicsContext, radius: CGFloat,
                                 x: CGFloat, y: CGFloat, length: CGFloat, width: CGFloat) {
        var drip = Path()
        drip.move(to: CGPoint(x: x - width / 2, y: y))
        drip.addQuadCurve(to: CGPoint(x: x, y: y + length),
                          control: CGPoint(x: x - width * 0.7, y: y + length * 0.55))
        drip.addQuadCurve(to: CGPoint(x: x + width / 2, y: y),
                          control: CGPoint(x: x + width * 0.7, y: y + length * 0.55))
        drip.closeSubpath()
        body.fill(drip, with: .color(CharacterColors.bodyBottom.opacity(0.85)))
    }

    // MARK: - Detail levels (scale adaptivity)

    /// Which details to draw at which size — readable at 16 px, richer at 128 px.
    struct DetailLevel {
        var radius: CGFloat

        var large: Bool { radius >= 32 }
        var gloss: Bool { radius >= 14 }
        var drips: Bool { radius >= 16 }
        var pupils: Bool { radius >= 8 }
        var brows: Bool { radius >= 10 }
    }
}

