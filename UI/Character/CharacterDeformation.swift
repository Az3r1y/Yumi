import Foundation
import CoreGraphics

/// A single body deformation to compose into a frame.
struct CharacterDeformation: Equatable, Sendable {
    /// scaleX/scaleY: 1 = none. Cartoon squash keeps volume: one axis below 1
    /// while the other is above 1.
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    /// Body lean (rotation), in radians.
    var lean: CGFloat = 0

    /// Vertical/horizontal offset in body radii (bounce, jump, hop).
    var offsetY: CGFloat = 0
    var offsetX: CGFloat = 0

    /// Bottom anchoring: 0 = centered, 1 = pinned to the ground line
    /// (a squash flattens toward the ground, not around the center).
    var grounded: CGFloat = 0

    /// Eye squash factor (eyes compress less than the body when squashing).
    var eyeSquashResistance: CGFloat = 0.6

    static let identity = CharacterDeformation()

    var isIdentity: Bool {
        self == .identity
    }

    /// Linear interpolation between two deformations.
    func interpolated(to other: CharacterDeformation, t: CGFloat) -> CharacterDeformation {
        CharacterDeformation(
            scaleX: scaleX + (other.scaleX - scaleX) * t,
            scaleY: scaleY + (other.scaleY - scaleY) * t,
            lean: lean + (other.lean - lean) * t,
            offsetY: offsetY + (other.offsetY - offsetY) * t,
            offsetX: offsetX + (other.offsetX - offsetX) * t,
            grounded: grounded + (other.grounded - grounded) * t,
            eyeSquashResistance: eyeSquashResistance)
    }

    /// A keyframe in a CharacterAnimation: deformation + easing toward it.
    struct Keyframe {
        var deformation: CharacterDeformation
        var duration: TimeInterval
        var ease: CharacterEasing = .inOut
    }

    /// Composed deformations.
    static func squash(amount: CGFloat) -> CharacterDeformation {
        CharacterDeformation(scaleX: 1 + amount, scaleY: 1 - amount, grounded: 1)
    }

    static func stretch(amount: CGFloat) -> CharacterDeformation {
        CharacterDeformation(scaleX: 1 - amount * 0.6, scaleY: 1 + amount, grounded: 0)
    }

    static func hop(height: CGFloat) -> CharacterDeformation {
        CharacterDeformation(offsetY: -height)
    }

    static func lean(angle: CGFloat) -> CharacterDeformation {
        CharacterDeformation(lean: angle)
    }

    static func offset(x: CGFloat, y: CGFloat) -> CharacterDeformation {
        CharacterDeformation(offsetY: y, offsetX: x)
    }

    /// Combines two deformations (offsets and scales multiply/accumulate).
    func combined(with other: CharacterDeformation) -> CharacterDeformation {
        CharacterDeformation(
            scaleX: scaleX * other.scaleX,
            scaleY: scaleY * other.scaleY,
            lean: lean + other.lean,
            offsetY: offsetY + other.offsetY,
            offsetX: offsetX + other.offsetX,
            grounded: max(grounded, other.grounded),
            eyeSquashResistance: eyeSquashResistance)
    }
}

/// Easing curves for animation keyframes.
enum CharacterEasing: Equatable, Sendable {
    case linear
    case inOut
    case out
    /// Overshoots past the target then settles — cartoon "life".
    case back

    func apply(_ t: CGFloat) -> CGFloat {
        let x = max(0, min(1, t))
        switch self {
        case .linear: return x
        case .inOut: return x < 0.5 ? 4*x*x*x : 1 - pow(-2*x+2, 3)/2
        case .out: return 1 - pow(1 - x, 3)
        case .back:
            let c1: CGFloat = 1.70158, c3 = c1 + 1
            return 1 + c3*pow(x-1, 3) + c1*pow(x-1, 2)
        }
    }
}
