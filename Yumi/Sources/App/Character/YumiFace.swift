import CoreGraphics

/// One face of the mock-up: the values of `BASE`, `MOODS` and `POSE_FACES` in reference.html.
/// The renderer eases every number, so faces blend instead of snapping.
struct YumiFace: Equatable, Sendable {
    var esl: CGFloat = 1    // eye scale, left and right
    var esr: CGFloat = 1
    var ps: CGFloat = 1     // pupil scale
    var tl: CGFloat = 0     // upper lid: 0 open, 1.1 shut
    var tr: CGFloat = 0
    var al: CGFloat = 0     // upper lid angle, degrees
    var ar: CGFloat = 0
    var bl: CGFloat = 0     // lower lid
    var br: CGFloat = 0
    var cl: CGFloat = 0     // opacity of the closed-eye stroke
    var cr: CGFloat = 0
    var tilt: CGFloat = 0   // head tilt, degrees
    /// A face with a look pins the gaze there (-1…1, y down) instead of following the pointer.
    var look: CGPoint? = nil

    // MOODS
    static let neutral   = YumiFace()
    static let happy     = YumiFace(bl: 0.42, br: 0.42)
    static let curious   = YumiFace(esl: 0.92, esr: 1.14, tilt: 7)
    static let focused   = YumiFace(tl: 0.38, tr: 0.38, look: CGPoint(x: 0, y: 0.5))
    static let thinking  = YumiFace(tl: 0.16, tr: 0.16, look: CGPoint(x: 0.8, y: -0.8))
    static let surprised = YumiFace(esl: 1.16, esr: 1.16, ps: 0.72)
    static let worried   = YumiFace(tl: 0.3, tr: 0.3, al: -16, ar: 16)
    static let annoyed   = YumiFace(tl: 0.4, tr: 0.4, al: 16, ar: -16)
    static let wink      = YumiFace(tr: 1.1, cr: 1)
    static let asleep    = YumiFace(tl: 1.1, tr: 1.1, cl: 1, cr: 1)

    // POSE_FACES: taken only while a pose or a habit plays
    static let weary     = YumiFace(tl: 0.46, tr: 0.46, look: CGPoint(x: 0.5, y: 0.55))           // las
    static let blank     = YumiFace(tl: 0.5, tr: 0.5, look: CGPoint(x: 0, y: -0.8))               // vide
    static let elsewhere = YumiFace(esl: 0.96, esr: 0.96, look: CGPoint(x: 0.95, y: -0.6))        // ailleurs
    static let squeezed  = YumiFace(ps: 0.85, tl: 0.3, tr: 0.3, al: 10, ar: -10, bl: 0.3, br: 0.3) // serre
    static let skyward   = YumiFace(esl: 1.14, esr: 1.14, ps: 0.8, look: CGPoint(x: 0, y: -1))    // haut
    static let shut      = YumiFace(tl: 1.1, tr: 1.1, cl: 1, cr: 1)                               // ferme
    /// Matcha: soothed and content, the lids low and the cheeks up.
    static let serene    = YumiFace(tl: 0.34, tr: 0.34, bl: 0.4, br: 0.4, tilt: -3)
}

extension YumiMood {
    var face: YumiFace {
        switch self {
        case .neutral:   return .neutral
        case .happy:     return .happy
        case .curious:   return .curious
        case .focused:   return .focused
        case .thinking:  return .thinking
        case .surprised: return .surprised
        case .worried:   return .worried
        case .annoyed:   return .annoyed
        case .wink:      return .wink
        case .asleep:    return .asleep
        }
    }
}

extension YumiRimTone {
    /// `RIMS` of the mock-up: the three stops of the rim gradient, left to right.
    var stops: [YumiRGB] {
        switch self {
        case .calm:  return [YumiRGB(hex: 0x5B8CFF), YumiRGB(hex: 0x8B6CFF), YumiRGB(hex: 0xF58AD9)]
        case .work:  return [YumiRGB(hex: 0x3F7BFF), YumiRGB(hex: 0x4FA0FF), YumiRGB(hex: 0x7FD0FF)]
        case .think: return [YumiRGB(hex: 0x7B5CFF), YumiRGB(hex: 0x9B7BFF), YumiRGB(hex: 0xC9A8FF)]
        case .warn:  return [YumiRGB(hex: 0xFF9A3D), YumiRGB(hex: 0xFFB547), YumiRGB(hex: 0xFFD37A)]
        case .error: return [YumiRGB(hex: 0xFF4D5E), YumiRGB(hex: 0xFF5D6C), YumiRGB(hex: 0xFF9AA4)]
        case .done:  return [YumiRGB(hex: 0x22C98A), YumiRGB(hex: 0x3DDC97), YumiRGB(hex: 0x9BF0C8)]
        case .joy:   return [YumiRGB(hex: 0xB07BFF), YumiRGB(hex: 0xF58AD9), YumiRGB(hex: 0xFFB3E6)]
        }
    }
}
