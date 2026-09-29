import Foundation
import CoreGraphics

// MARK: - Animation kinds

/// Ambient loops: run forever while the state holds.
enum CharacterAmbientAnimation: Equatable, Sendable, CaseIterable {
    case breathe
    case blink
    case sleep
    case bounce
}

/// One-shot animations: play once (or per trigger), then the pose returns to
/// the state's resting deformation.
enum CharacterOneShotAnimation: Equatable, Sendable, CaseIterable {
    case jump
    case celebrate
    case shake
    case peek
    case fall
}

// MARK: - Keyframe animation primitives

/// A timed sequence of body deformations, played once.
struct CharacterAnimation: Sendable {
    var keyframes: [CharacterDeformation.Keyframe]
    /// Duration of the full sequence (derived from keyframes).
    var duration: TimeInterval { keyframes.reduce(0) { $0 + $1.duration } }

    /// Samples the deformation at time t (seconds since sequence start).
    func sample(at t: TimeInterval) -> CharacterDeformation {
        var remaining = max(0, t)
        var current = CharacterDeformation.identity

        for keyframe in keyframes {
            if remaining <= keyframe.duration {
                let progress = keyframe.duration == 0 ? 1 : CGFloat(remaining / keyframe.duration)
                let eased = keyframe.ease.apply(progress)
                return current.interpolated(to: keyframe.deformation, t: eased)
            }
            remaining -= keyframe.duration
            current = keyframe.deformation
        }
        // Past the end: rest at the last keyframe.
        return keyframes.last?.deformation ?? .identity
    }
}

// MARK: - One-shot definitions

extension CharacterAnimation {
    /// Success: anticipation (squash) → jump (stretch) → overshoot → settle.
    /// The cartoon pattern: squash → stretch → rebound.
    static func celebrate() -> CharacterAnimation {
        CharacterAnimation(keyframes: [
            .init(deformation: .squash(amount: 0.22), duration: 0.12, ease: .out),
            .init(deformation: .stretch(amount: 0.30).combined(with: .hop(height: 0.9)), duration: 0.16, ease: .out),
            .init(deformation: .squash(amount: 0.18).combined(with: .hop(height: 0.25)), duration: 0.14, ease: .inOut),
            .init(deformation: .stretch(amount: 0.12).combined(with: .hop(height: 0.55)), duration: 0.13, ease: .out),
            .init(deformation: .squash(amount: 0.10), duration: 0.12, ease: .inOut),
            .init(deformation: .identity, duration: 0.20, ease: .back),
        ])
    }

    /// Error: anticipation → violent shake → settle to worried rest.
    static func errorShake() -> CharacterAnimation {
        CharacterAnimation(keyframes: [
            .init(deformation: .squash(amount: 0.14), duration: 0.10, ease: .out),
            .init(deformation: .offset(x: -0.12, y: 0), duration: 0.05, ease: .linear),
            .init(deformation: .offset(x: 0.12, y: 0), duration: 0.05, ease: .linear),
            .init(deformation: .offset(x: -0.08, y: 0), duration: 0.05, ease: .linear),
            .init(deformation: .offset(x: 0.05, y: 0), duration: 0.05, ease: .linear),
            .init(deformation: .identity, duration: 0.16, ease: .inOut),
        ])
    }

    /// Simple happy jump (one hop).
    static func jump() -> CharacterAnimation {
        CharacterAnimation(keyframes: [
            .init(deformation: .squash(amount: 0.18), duration: 0.10, ease: .out),
            .init(deformation: .stretch(amount: 0.25).combined(with: .hop(height: 0.7)), duration: 0.15, ease: .out),
            .init(deformation: .squash(amount: 0.12).combined(with: .hop(height: 0.1)), duration: 0.12, ease: .inOut),
            .init(deformation: .identity, duration: 0.18, ease: .back),
        ])
    }

    /// Peek from the notch: quick lean out, hold, back.
    static func peek() -> CharacterAnimation {
        CharacterAnimation(keyframes: [
            .init(deformation: .lean(angle: 0.12).combined(with: .offset(x: 0.1, y: 0)), duration: 0.18, ease: .out),
            .init(deformation: .lean(angle: 0.10).combined(with: .offset(x: 0.1, y: 0)), duration: 0.5, ease: .linear),
            .init(deformation: .identity, duration: 0.22, ease: .inOut),
        ])
    }

    /// Fall: startled drop (used on errors with reduced-motion off).
    static func fall() -> CharacterAnimation {
        CharacterAnimation(keyframes: [
            .init(deformation: .stretch(amount: 0.2), duration: 0.08, ease: .inOut),
            .init(deformation: .squash(amount: 0.25), duration: 0.10, ease: .out),
            .init(deformation: .identity, duration: 0.25, ease: .back),
        ])
    }
}

// MARK: - Ambient definitions

/// An ambient loop + the period it runs on.
struct AmbientLoop: Sendable {
    var animation: CharacterAnimation
    var period: TimeInterval

    /// Samples the loop cyclically.
    func sample(at t: TimeInterval) -> CharacterDeformation {
        let phase = t.truncatingRemainder(dividingBy: period)
        return animation.sample(at: phase)
    }
}

extension AmbientLoop {
    /// Gentle breathing — always running unless sleeping.
    static let breathe = AmbientLoop(
        animation: CharacterAnimation(keyframes: [
            .init(deformation: .identity, duration: 1.2, ease: .inOut),
            .init(deformation: .squash(amount: 0.03), duration: 1.4, ease: .inOut),
            .init(deformation: .identity, duration: 1.2, ease: .inOut),
        ]),
        period: 3.8)

    /// Sleeping: slow deep breaths with slight slump.
    static let sleep = AmbientLoop(
        animation: CharacterAnimation(keyframes: [
            .init(deformation: .identity, duration: 1.4, ease: .inOut),
            .init(deformation: .squash(amount: 0.09).combined(with: .lean(angle: 0.06)), duration: 2.0, ease: .inOut),
            .init(deformation: .identity, duration: 1.4, ease: .inOut),
        ]),
        period: 4.8)

    /// Impatient bounce (waiting/happy states).
    static let bounce = AmbientLoop(
        animation: CharacterAnimation(keyframes: [
            .init(deformation: .identity, duration: 0.24, ease: .out),
            .init(deformation: .squash(amount: 0.05), duration: 0.1, ease: .inOut),
            .init(deformation: .hop(height: 0.06), duration: 0.16, ease: .out),
            .init(deformation: .squash(amount: 0.03), duration: 0.08, ease: .inOut),
            .init(deformation: .identity, duration: 0.22, ease: .inOut),
        ]),
        period: 0.8)
}
