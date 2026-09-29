import SwiftUI
import CoreGraphics

/// PLACEHOLDER renderer — deliberately simple and slightly crude.
///
/// Its only job is to exercise the character system (states, expressions,
/// deformations, reactions, scale, reduced motion) until the real Yumi
/// art direction lands. Do not polish: every visual decision here (blob
/// silhouette, dot eyes, flat colors) is disposable. When the DA is
/// approved, replace via CharacterViewFactory — this file goes away.
struct TemporaryCharacterRenderer: CharacterRenderer {

    func draw(pose: CharacterPose, in context: inout GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) * 0.5 * 0.72
        guard radius > 1 else { return }

        let f = pose.face
        let d = pose.deformation
        let cx = size.width / 2 + d.offsetX * radius
        // Bottom anchor: deformations pivot around the ground line.
        let groundY = size.height / 2 + radius * 1.02
        let cy = groundY - radius * 0.95 + d.offsetY * radius

        var c = context
        c.translateBy(x: cx, y: cy)
        c.rotate(by: .radians(d.lean))
        c.scaleBy(x: d.scaleX, y: d.scaleY)
        c.translateBy(x: 0, y: radius * (1 - d.scaleY))

        // Body: one flat organic blob.
        let bodyPath = blobPath(radius: radius)
        c.fill(bodyPath, with: .color(CharacterColors.body))

        // Eyes: two dots. Openness shrinks them; pupil offset shifts them.
        let spacing = radius * 0.40 * f.eyeSpacing
        let eyeY = -radius * 0.16 * f.eyeHeight
        let eyeR = radius * 0.13 * f.eyeScale * max(0.15, f.eyeOpenness)
        for side in [-1.0, 1.0] {
            let ex = CGFloat(side) * spacing + f.pupilOffset.width * radius * 0.5
            let ey = eyeY + f.pupilOffset.height * radius * 0.5
            let eyeRect = CGRect(x: ex - eyeR, y: ey - eyeR, width: eyeR * 2, height: eyeR * 2)
            c.fill(Path(ellipseIn: eyeRect), with: .color(CharacterColors.ink))
        }

        // Brows: two short strokes (browRotation tilts them).
        if radius >= 10 {
            let browY = eyeY - radius * 0.24 * f.browHeight
            let len = radius * 0.14
            for side in [-1.0, 1.0] {
                let bx = CGFloat(side) * spacing * 0.95
                var brow = Path()
                brow.move(to: CGPoint(x: bx - CGFloat(side) * len * 0.5,
                                      y: browY - CGFloat(side) * sin(f.browRotation) * len * 0.5))
                brow.addLine(to: CGPoint(x: bx + CGFloat(side) * len * 0.5,
                                         y: browY + CGFloat(side) * sin(f.browRotation) * len * 0.5))
                c.stroke(brow, with: .color(CharacterColors.ink),
                         style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
            }
        }

        // Mouth: a minimal shape per MouthShape.
        let mouthY = radius * 0.30
        let mw = radius * 0.18 * f.mouthScale
        var mouth = Path()
        switch f.mouth {
        case .neutral:
            mouth.move(to: CGPoint(x: -mw / 2, y: mouthY))
            mouth.addLine(to: CGPoint(x: mw / 2, y: mouthY))
            c.stroke(mouth, with: .color(CharacterColors.ink),
                     style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        case .flat:
            mouth.move(to: CGPoint(x: -mw * 0.8, y: mouthY))
            mouth.addLine(to: CGPoint(x: mw * 0.8, y: mouthY))
            c.stroke(mouth, with: .color(CharacterColors.ink),
                     style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        case .smallOpen:
            let mh = mw * 0.55
            c.fill(Path(ellipseIn: CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)),
                   with: .color(CharacterColors.ink))
        case .wideOpen:
            let mh = mw * 0.95
            c.fill(Path(ellipseIn: CGRect(x: -mw / 2, y: mouthY - mh / 2, width: mw, height: mh)),
                   with: .color(CharacterColors.ink))
        case .wavy:
            let seg = mw / 4
            mouth.move(to: CGPoint(x: -mw / 2, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: -mw / 2 + seg * 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg, y: mouthY - mw * 0.22))
            mouth.addQuadCurve(to: CGPoint(x: mw / 2, y: mouthY),
                               control: CGPoint(x: -mw / 2 + seg * 3, y: mouthY + mw * 0.22))
            c.stroke(mouth, with: .color(CharacterColors.ink),
                     style: StrokeStyle(lineWidth: max(1, radius * 0.045), lineCap: .round))
        case .smile:
            mouth.addArc(center: CGPoint(x: 0, y: mouthY - mw * 0.3),
                         radius: mw * 0.66,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            c.stroke(mouth, with: .color(CharacterColors.ink),
                     style: StrokeStyle(lineWidth: max(1, radius * 0.05), lineCap: .round))
        }
    }

    /// Placeholder silhouette: a slightly squashed organic blob (closed
    /// Catmull-Rom spline). Disposable by design.
    private func blobPath(radius: CGFloat) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (-0.80, 0.10), (-0.60, -0.55), (0.10, -0.70), (0.72, -0.35),
            (0.85, 0.20), (0.55, 0.60), (-0.10, 0.68), (-0.68, 0.45),
        ]
        return CharacterGeometry.closedSpline(
            points.map { CGPoint(x: $0.0 * radius, y: $0.1 * radius) })
    }
}
