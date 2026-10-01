import CoreGraphics

// `POSE_FX` of design/yumi/maquette/reference.html: each pose is a short list of beats that
// change the targets and the stiffness of the springs. Times are in milliseconds.

extension YumiBlob {

    private static func crouch(_ b: YumiBlob) { b.hard(); b.th = 0.66 }
    private static func leap(_ b: YumiBlob) { b.soft(); b.th = 1.18; b.vy = -190; b.air = true }
    private static func back(_ b: YumiBlob) { b.tempFace = nil }

    static func steps(for pose: YumiPose) -> [Step] {
        switch pose {
        case .squash:
            // rise a little, slam flat with the eyes squeezed, hold, then spring back up and wobble
            return [
                Step(at: 0)    { b in b.k = 300; b.c = 22; b.th = 1.12 },
                Step(at: 130)  { b in b.hard(); b.th = 0.5; b.tempFace = .squeezed },
                Step(at: 240)  { b in b.splat(3, 1) },
                Step(at: 780)  { b in b.soft(); b.c = 7; b.th = 1; b.tempFace = .surprised },
                Step(at: 1250, run: back),
            ]
        case .stretch:
            // crouch, reach up thin while looking at the sky and swaying, then snap back
            return [
                Step(at: 0)    { b in b.hard(); b.th = 0.8 },
                Step(at: 170)  { b in b.k = 110; b.c = 10; b.th = 1.45; b.leanTarget = 5; b.tempFace = .skyward },
                Step(at: 560)  { b in b.leanTarget = -5 },
                Step(at: 860)  { b in b.leanTarget = 0; b.k = 210; b.c = 6.5; b.th = 1 },
                Step(at: 1250, run: back),
            ]
        case .shake:
            // eyes shut, the top whips left and right behind the base and throws droplets,
            // then he comes to, a bit dazed
            return [
                Step(at: 0)    { b in b.tempFace = .shut; b.kl = 300; b.cl = 10; b.th = 0.95; b.leanTarget = 16; b.fling(-1) },
                Step(at: 90)   { b in b.leanTarget = -16; b.fling(1) },
                Step(at: 180)  { b in b.leanTarget = 14; b.fling(-1) },
                Step(at: 270)  { b in b.leanTarget = -14; b.fling(1) },
                Step(at: 360)  { b in b.leanTarget = 10; b.fling(-1) },
                Step(at: 450)  { b in b.leanTarget = -8 },
                Step(at: 540)  { b in b.leanTarget = 0; b.th = 1; b.kl = 150; b.cl = 6 },
                Step(at: 700)  { b in b.tempFace = .surprised },
                Step(at: 1050, run: back),
            ]
        case .jump:
            return [Step(at: 0, run: crouch), Step(at: 150, run: leap)]
        case .celebrate:
            return [Step(at: 0, run: crouch), Step(at: 130, run: leap), Step(at: 640, run: crouch), Step(at: 770, run: leap)]
        case .wave:
            return [
                Step(at: 0)    { b in b.kl = 55; b.cl = 7; b.th = 1.05; b.leanTarget = 7 },
                Step(at: 280)  { b in b.leanTarget = -7 },
                Step(at: 560)  { b in b.leanTarget = 7 },
                Step(at: 840)  { b in b.leanTarget = -7 },
                Step(at: 1120) { b in b.leanTarget = 0; b.th = 1 },
            ]
        case .dip:
            return [Step(at: 0) { b in b.hard(); b.th = 0.76 }, Step(at: 250) { b in b.soft(); b.th = 1 }]
        case .arrive:
            return [Step(at: 0) { b in b.h = 1.45; b.vh = 0; b.c = 7 }]
        case .boing:
            return [Step(at: 0) { b in b.h = 0.7; b.vh = 0; b.c = 7 }]
        case .pop:
            return [Step(at: 0) { b in b.vh -= 2.4 }]
        }
    }
}

extension YumiPose {
    /// `POSE_MS`: how long the pose is considered to be playing, in seconds.
    var duration: Double {
        switch self {
        case .jump:      return 0.9
        case .stretch:   return 1.3
        case .squash:    return 1.4
        case .shake:     return 1.1
        case .celebrate: return 1.6
        case .wave:      return 1.52
        case .dip:       return 0.4
        case .arrive:    return 0.6
        case .pop:       return 0.4
        case .boing:     return 0.7
        }
    }

    /// The two small arms come out for these poses.
    var showsArms: Bool { self == .celebrate || self == .wave }
    /// Three sparks around the head.
    var showsSparks: Bool { self == .celebrate }
}

/// Keyframes that the mock-up runs in CSS while a pose plays (`p-arml`, `p-armr`, `p-spark`).
enum YumiPoseExtras {
    /// Arms and sparks both run for 1.5 s.
    static let duration: CGFloat = 1.5

    /// Opacity and angle (degrees) of the left arm at time `t` (seconds). The right arm mirrors it.
    static func arm(at t: CGFloat) -> (opacity: CGFloat, angle: CGFloat)? {
        guard t >= 0, t <= duration else { return nil }
        let p = t / duration
        let opacity = yumiKeyframes(p, [(0, 0), (0.10, 1), (0.88, 1), (1, 0)], .easeInOut)
        let angle = yumiKeyframes(p, [(0, 45), (0.22, -14), (0.37, 16), (0.52, -14), (0.66, 16), (0.80, -14), (1, 45)], .easeInOut)
        return (opacity, angle)
    }

    /// Position, base scale and delay of the three sparks.
    static let sparks: [(at: CGPoint, scale: CGFloat, delay: CGFloat)] = [
        (CGPoint(x: 8, y: 14), 1, 0), (CGPoint(x: 92, y: 10), 1.3, 0.15), (CGPoint(x: 50, y: -4), 0.9, 0.3),
    ]

    static func spark(at t: CGFloat) -> (opacity: CGFloat, scale: CGFloat, angle: CGFloat, rise: CGFloat)? {
        guard t >= 0, t <= duration else { return nil }
        let p = t / duration
        return (yumiKeyframes(p, [(0, 0), (0.3, 1), (1, 0)], .easeOut),
                yumiKeyframes(p, [(0, 0.2), (0.3, 1.1), (1, 0.6)], .easeOut),
                yumiKeyframes(p, [(0, 0), (0.3, 20), (1, 60)], .easeOut),
                yumiKeyframes(p, [(0, 0), (0.3, 0), (1, -6)], .easeOut))
    }
}
