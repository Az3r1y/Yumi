import CoreGraphics

/// The mouth of the character (kept minimal — no ultra-kawaii grins).
enum MouthShape: Hashable, Sendable {
    case neutral        // short flat line
    case smallOpen      // small rounded open mouth (talking, surprise)
    case wideOpen       // big open mouth (excited, panicked)
    case flat           // long flat line (annoyed)
    case wavy           // wavy line (confused, uneasy)
    case smile          // gentle small smile (not kawaii)
}

/// A fully parametric face. Expressions are *values* of this struct —
/// no images, no per-expression assets. The renderer interpolates between
/// faces to get smooth expression changes.
struct CharacterFace: Hashable, Sendable {
    // Eyes
    var eyeScale: CGFloat = 1           // overall eye size multiplier
    var eyeSpacing: CGFloat = 1         // horizontal distance multiplier
    var eyeHeight: CGFloat = 1          // vertical position multiplier
    var eyeOpenness: CGFloat = 1        // 0 = closed, 1 = fully open
    var pupilOffset: CGSize = .zero     // look direction, in body radii

    // Brows (short strokes above the eyes)
    var browHeight: CGFloat = 1         // 0 = on the eyes, 1 = high
    var browAngle: CGFloat = 0          // radians; positive = inner ends up (curious)
    var browRotation: CGFloat = 0       // radians; secondary tilt used by renderers
    var eyeRotation: CGFloat = 0        // radians; whole-eye tilt (future renderer)

    // Mouth
    var mouth: MouthShape = .neutral
    var mouthScale: CGFloat = 1

    static let `default` = CharacterFace()

    // MARK: - Expressions (all faces are simple combinations of parameters)

    static let idle = CharacterFace(browHeight: 0.85)

    static let sleepy = CharacterFace(
        eyeScale: 0.9, eyeOpenness: 0.18,
        browHeight: 0.55, browAngle: -0.05,
        mouth: .neutral, mouthScale: 0.85)

    static let curious = CharacterFace(
        eyeScale: 1.15,
        pupilOffset: CGSize(width: 0.10, height: -0.06),
        browHeight: 1.0, browAngle: 0.18,
        mouth: .smallOpen, mouthScale: 0.8)

    static let focused = CharacterFace(
        eyeScale: 0.85, eyeSpacing: 0.92,
        pupilOffset: CGSize(width: 0.08, height: 0.04),
        browHeight: 0.72, browAngle: -0.14,
        mouth: .flat, mouthScale: 0.8)

    static let thinking = CharacterFace(
        eyeScale: 0.95, eyeSpacing: 0.95,
        pupilOffset: CGSize(width: 0.14, height: 0.0),
        browHeight: 0.9, browAngle: -0.08,
        mouth: .neutral, mouthScale: 0.9)

    static let happy = CharacterFace(
        eyeScale: 1.05, eyeHeight: 0.95,
        browHeight: 0.95, browAngle: 0.06,
        mouth: .smile)

    static let excited = CharacterFace(
        eyeScale: 1.25, eyeHeight: 0.92,
        browHeight: 1.05, browAngle: 0.12,
        mouth: .wideOpen, mouthScale: 0.9)

    static let worried = CharacterFace(
        eyeScale: 1.05,
        browHeight: 0.62, browAngle: -0.22,
        mouth: .wavy, mouthScale: 0.85)

    static let confused = CharacterFace(
        eyeScale: 1.0, eyeSpacing: 1.06,
        pupilOffset: CGSize(width: -0.10, height: 0.02),
        browHeight: 0.85, browAngle: 0.24,
        mouth: .wavy, mouthScale: 0.9)

    static let annoyed = CharacterFace(
        eyeScale: 0.8, eyeHeight: 1.05,
        browHeight: 0.55, browAngle: -0.3,
        mouth: .flat)

    static let surprised = CharacterFace(
        eyeScale: 1.4, eyeHeight: 0.9,
        browHeight: 1.1,
        mouth: .smallOpen, mouthScale: 1.1)

    static let panicked = CharacterFace(
        eyeScale: 1.5, eyeHeight: 0.85,
        browHeight: 1.15, browAngle: -0.12,
        mouth: .wideOpen, mouthScale: 1.25)
}
