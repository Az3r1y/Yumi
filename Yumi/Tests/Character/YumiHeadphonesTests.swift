import Foundation
import Testing

struct YumiHeadphonesTests {
    @Test func facingAheadTheCupsSitOnBothEars() {
        let ears = YumiHeadphones.ears(yaw: 0)
        #expect(abs(ears.left.x - 7.5) < 0.01 && abs(ears.right.x - 92.5) < 0.01)
        #expect(ears.left.opacity == 1 && ears.right.opacity == 1)
    }

    @Test func turningRightTheRightEarGoesBehindAndTheLeftComesRound() {
        let ears = YumiHeadphones.ears(yaw: 0.5)
        #expect(ears.left.x > 7.5 && ears.right.x < 92.5)
        #expect(ears.left.width > ears.right.width)
        #expect(ears.right.opacity == 1)
        #expect(YumiHeadphones.ears(yaw: 1.4).right.opacity < 0.01)
    }
}
