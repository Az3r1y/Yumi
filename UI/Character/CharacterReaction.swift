import Foundation

/// A temporary reaction layered on top of the current character state.
/// Reactions never replace the state: when they expire, the character
/// returns to whatever it was doing.
struct CharacterReaction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case celebrate      // success: jump + excited face
        case error          // failure: shake + worried face
        case surprise       // startled: wide eyes
        case attention      // user interaction: peek/hop + curious face
    }

    var kind: Kind
    var startedAt: TimeInterval
    var duration: TimeInterval

    /// Higher priority wins when several reactions are pending.
    var priority: Int {
        switch kind {
        case .error: return 3
        case .surprise: return 2
        case .celebrate: return 1
        case .attention: return 0
        }
    }

    func isActive(at now: TimeInterval) -> Bool {
        now < startedAt + duration
    }

    /// Normalized progress in [0, 1].
    func progress(at now: TimeInterval) -> Double {
        min(1, max(0, (now - startedAt) / duration))
    }

    /// The face held during this reaction.
    var face: CharacterFace {
        switch kind {
        case .celebrate: return .excited
        case .error: return .worried
        case .surprise: return .surprised
        case .attention: return .curious
        }
    }

    /// The one-shot body animation played at the start of the reaction.
    var bodyAnimation: CharacterAnimation {
        switch kind {
        case .celebrate: return .celebrate()
        case .error: return .errorShake()
        case .surprise: return .fall()
        case .attention: return .peek()
        }
    }

    /// Default durations per kind.
    static func duration(for kind: Kind) -> TimeInterval {
        switch kind {
        case .celebrate: return 1.6
        case .error: return 1.1
        case .surprise: return 1.2
        case .attention: return 1.4
        }
    }

    init(kind: Kind, startedAt: TimeInterval, duration: TimeInterval? = nil) {
        self.kind = kind
        self.startedAt = startedAt
        self.duration = duration ?? Self.duration(for: kind)
    }
}
