import SwiftUI
import CoreGraphics

/// Contract for drawing one frame of the character.
///
/// This is the seam between the Character System's logic (states, faces,
/// deformations, animation controller) and the artwork. The logic produces a
/// `CharacterPose`; a renderer decides how it looks. The final Yumi art
/// direction will ship as a new conforming type — nothing else changes.
protocol CharacterRenderer: Sendable {
    /// Draws one pose into the given context, filling the canvas `size`.
    ///
    /// Implementations must stay scale-adaptive (the pose renders from ~16 px
    /// to 128+ px): at small sizes keep the silhouette and eyes readable and
    /// drop decorative detail.
    func draw(pose: CharacterPose, in context: inout GraphicsContext, size: CGSize)
}

/// Single place where the app binds which renderer draws Yumi.
/// Swapping the artwork later = changing `make()` and nothing else.
enum CharacterViewFactory {
    /// The currently bound renderer. Placeholder until the final DA lands.
    static func make() -> any CharacterRenderer {
        TemporaryCharacterRenderer()
    }
}

/// Geometry helpers shared by renderers (art-agnostic).
enum CharacterGeometry {
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
}
