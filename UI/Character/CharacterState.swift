import Foundation

/// Presentation states of the character — deliberately distinct from the Core
/// session states. The character layer decides how to *show* what the Core
/// reports: a working session may be shown as focused, a permission request
/// as curious, etc.
enum CharacterState: Equatable, Sendable, CaseIterable {
    case idle
    case sleepy
    case working
    case waiting
    case happy
    case errored
    case thinking

    /// The face this state rests on (the animation controller adds breathing,
    /// blinking, reactions on top of it).
    var face: CharacterFace {
        switch self {
        case .idle: return .idle
        case .sleepy: return .sleepy
        case .working: return .focused
        case .waiting: return .curious
        case .happy: return .happy
        case .errored: return .worried
        case .thinking: return .thinking
        }
    }

    /// Ambient animation (loops) while the state holds.
    var ambient: CharacterAmbientAnimation {
        switch self {
        case .idle: return .breathe
        case .sleepy: return .sleep
        case .working: return .breathe
        case .waiting: return .bounce
        case .happy: return .bounce
        case .errored: return .breathe
        case .thinking: return .breathe
        }
    }

    /// Whether the body keeps deforming between keyframes in this state.
    var allowsIdleMotion: Bool {
        self != .sleepy
    }
}

/// The full visual configuration of the character at a given moment:
/// state → face + ambient loop, plus the deformation currently applied.
/// `time`/`anchor` carry the render clock so blinks can be computed by the
/// view layer (defaults keep Equatable tests trivial).
struct CharacterPose: Equatable, Sendable {
    var state: CharacterState
    var face: CharacterFace
    var deformation: CharacterDeformation
    var time: TimeInterval = 0
    var anchor: TimeInterval = 0
}
