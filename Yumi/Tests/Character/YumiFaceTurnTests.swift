import CoreGraphics
import Testing

@Suite struct YumiFaceTurnTests {
    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
    }

    /// The middle of the two eyes, where the head turn puts them.
    private func eyesMiddle(yaw: CGFloat, pitch: CGFloat) -> CGPoint {
        let l = CGPoint.zero.applying(YumiFaceTurn.eye(-1, yaw: yaw, pitch: pitch))
        let r = CGPoint.zero.applying(YumiFaceTurn.eye(1, yaw: yaw, pitch: pitch))
        return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
    }

    @Test func atRestTheFaceDoesNotMove() {
        #expect(YumiFaceTurn.face(yaw: 0, pitch: 0).isIdentity)
    }

    @Test func atRestTheEyesSitEitherSideOfTheMiddle() {
        let l = CGPoint.zero.applying(YumiFaceTurn.eye(-1, yaw: 0, pitch: 0))
        let r = CGPoint.zero.applying(YumiFaceTurn.eye(1, yaw: 0, pitch: 0))
        #expect(abs(l.x - (50 - 13.0)) < 0.1 && abs(r.x - (50 + 13.0)) < 0.1)
        #expect(l.y == 45 && r.y == 45)
    }

    /// What he wears on the face follows his eyes when he looks towards the pointer
    /// (the engine turns him by up to 0.5 sideways and 0.32 up or down).
    @Test(arguments: [(CGFloat(0.5), CGFloat(0)), (-0.5, 0), (0, 0.32), (0, -0.32), (0.5, -0.32), (-0.3, 0.2)])
    func theMiddleOfTheFaceFollowsTheEyes(yaw: CGFloat, pitch: CGFloat) {
        let middle = YumiFaceTurn.middle.applying(YumiFaceTurn.face(yaw: yaw, pitch: pitch))
        #expect(close(middle, eyesMiddle(yaw: yaw, pitch: pitch)))
    }

    @Test func lookingRightMovesTheFaceRight() {
        let middle = YumiFaceTurn.middle.applying(YumiFaceTurn.face(yaw: 0.5, pitch: 0))
        #expect(middle.x > 60)
    }
}
