import CoreGraphics

/// The eyes sit on a sphere: when the head turns (yaw, pitch: towards the pointer, a glance,
/// a pinned look) they slide sideways and the one going round the edge narrows. What is worn
/// on the face rides the same sphere, so the eyes and the face transforms come from here.
enum YumiFaceTurn {
    /// The middle of the eyes, in the 100-wide character space.
    static let middle = CGPoint(x: 50, y: 45)
    /// How far the eyes travel on the sphere, sideways and up and down.
    static let reach = CGSize(width: 40.1, height: 30)
    /// Where each eye sits on the sphere at rest, in radians either side of the middle.
    static let eyeAngle: CGFloat = 0.33

    /// One eye (`side` -1 for the left, 1 for the right): takes a drawing centred on (0, 0)
    /// to where that eye is, narrowed as it goes round.
    static func eye(_ side: CGFloat, yaw: CGFloat, pitch: CGFloat) -> CGAffineTransform {
        let ya = side * eyeAngle + yaw
        return CGAffineTransform(a: max(0.35, cos(ya)), b: 0, c: 0, d: max(0.6, cos(pitch)),
                                 tx: middle.x + sin(ya) * cos(pitch) * reach.width,
                                 ty: middle.y + sin(pitch) * reach.height)
    }

    /// The whole face: moves the middle of the face as the middle of the two eyes moves, and
    /// narrows it the same way, so glasses, a cigarette or a cup follow the eyes.
    static func face(yaw: CGFloat, pitch: CGFloat) -> CGAffineTransform {
        let kx = max(0.6, cos(yaw)), ky = max(0.6, cos(pitch))
        return CGAffineTransform(a: kx, b: 0, c: 0, d: ky,
                                 tx: middle.x * (1 - kx) + sin(yaw) * cos(pitch) * reach.width * cos(eyeAngle),
                                 ty: middle.y * (1 - ky) + sin(pitch) * reach.height)
    }
}

/// Where the cups of the headphones are drawn: on the ears, at the two sides of his head seen as
/// a sphere turned by `yaw`.
enum YumiHeadphones {
    struct Ear: Equatable {
        /// The middle of the cup, in the 100-unit box.
        var x: CGFloat
        var width: CGFloat
        /// 1 in front, fading out as the ear goes behind the head.
        var opacity: CGFloat
    }

    static func ears(yaw: CGFloat, width: CGFloat = 1) -> (left: Ear, right: Ear) {
        func ear(_ side: CGFloat) -> Ear {
            let angle = side * .pi / 2 + yaw
            // > 0: the ear faces the viewer
            let depth = cos(angle)
            // His outline does not turn with the head: the ear going behind stays in sight,
            // only narrower, and fades only past a large turn
            return Ear(x: 50 + sin(angle) * 42.5 * width,
                       width: max(6, 11 + 6 * depth),
                       opacity: max(0, min(1, (depth + 0.9) / 0.3)))
        }
        return (ear(-1), ear(1))
    }
}
