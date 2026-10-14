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
