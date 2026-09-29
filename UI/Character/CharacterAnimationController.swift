import Foundation
import CoreGraphics

/// The character's brain: composes the current state's face and ambient
/// animation with any temporary reaction into a single pose per frame.
///
/// Pure presentation logic: no SwiftUI, no AppKit, no Core types. Time-based
/// (not frame-based) so the pose depends only on the clock, which makes the
/// whole controller testable without rendering.
@MainActor
final class CharacterAnimationController: ObservableObject {
    // MARK: - Inputs

    @Published private(set) var state: CharacterState = .idle

    // MARK: - Internal presentation timeline

    private var currentReaction: CharacterReaction?
    private var reactionAnimationStart: TimeInterval = 0
    /// One-shot animation currently playing (independent of reactions).
    private var oneShot: (animation: CharacterAnimation, start: TimeInterval)?

    // Free gaze: the eyes wander on their own instead of staring at a fixed
    // point. Amplitudes are in pupil-offset units (body radii fractions).
    private var gazeFrom: CGSize = .zero
    private(set) var gazeTarget: CGSize = .zero
    private var gazeStart: TimeInterval = 0
    private var nextGazeAt: TimeInterval = 0
    static let gazeAmplitude = CGSize(width: 0.18, height: 0.12)
    static let gazeInterval: ClosedRange<TimeInterval> = 1.4...4.0

    /// Monotonic timeline anchor; poses depend only on (now - anchor).
    private var anchor: TimeInterval = 0

    /// Whether to tone animations down (accessibility "Reduce Motion").
    private(set) var reduceMotion: Bool

    // MARK: - Init

    init(reduceMotion: Bool = false) {
        self.reduceMotion = reduceMotion
    }

    // MARK: - State

    func setState(_ newState: CharacterState) {
        guard newState != state else { return }
        state = newState
    }

    /// Toggles reduced motion (wired to NSWorkspace accessibility options).
    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
    }

    // MARK: - Reactions & one-shots

    /// Plays a temporary reaction on top of the current state. A higher
    /// priority reaction replaces a lower one; a lower one is ignored while
    /// a higher is active.
    func playReaction(_ kind: CharacterReaction.Kind, at now: TimeInterval) {
        let reaction = CharacterReaction(kind: kind, startedAt: now)
        if let current = currentReaction, current.isActive(at: now),
           current.priority > reaction.priority {
            return  // keep the more important reaction running
        }
        currentReaction = reaction
        reactionAnimationStart = now
        anchor = now
    }

    /// Plays a one-shot body animation (without a reaction face).
    func playOneShot(_ animation: CharacterOneShotAnimation, at now: TimeInterval) {
        oneShot = (animation: Self.animation(for: animation), start: now)
    }

    /// True while a one-shot is still playing (views use this to keep the
    /// timeline running).
    var isAnimating: Bool {
        guard let oneShot else { return false }
        return ProcessInfo.processInfo.systemUptime - oneShot.start < oneShot.animation.duration
    }

    // MARK: - Per-frame pose

    /// The pose at time `now` (monotonic seconds, e.g. systemUptime).
    func pose(at now: TimeInterval) -> CharacterPose {
        let t = now - anchor

        // 1. Which face?
        var face: CharacterFace
        var deformation = CharacterDeformation.identity

        if let reaction = currentReaction, reaction.isActive(at: now) {
            face = reaction.face
            let elapsed = now - reactionAnimationStart
            let anim = reaction.bodyAnimation
            if elapsed < anim.duration {
                deformation = anim.sample(at: elapsed)
            }
        } else if currentReaction != nil {
            currentReaction = nil  // expired — back to the state
            face = state.face
        } else {
            face = state.face
        }

        // 2. Ambient loop on top (unless a one-shot is controlling the body).
        let oneShotActive: Bool
        if let shot = oneShot {
            let elapsed = now - shot.start
            if elapsed < shot.animation.duration {
                deformation = deformation.combined(with: shot.animation.sample(at: elapsed))
                oneShotActive = true
            } else {
                oneShot = nil
                oneShotActive = false
            }
        } else {
            oneShotActive = false
        }

        if !oneShotActive {
            let ambient = Self.ambientLoop(for: state.ambient)
            deformation = deformation.combined(with: ambient.sample(at: t))
        }

        // 3. Free gaze: while no reaction holds the face, let the eyes look
        // around on their own (states with expressive fixed looks keep them).
        if currentReaction == nil && Self.stateHasFreeGaze(state) {
            refreshGazeIfNeeded(at: now)
            face.pupilOffset = currentGaze(at: now)
        }

        // 4. Reduced motion: clamp amplitudes, keep state legibility.
        if reduceMotion {
            deformation = Self.damped(deformation)
        }

        return CharacterPose(state: state, face: face, deformation: deformation)
    }

    // MARK: - Static configuration (testable, no instance state)

    static func animation(for oneShot: CharacterOneShotAnimation) -> CharacterAnimation {
        switch oneShot {
        case .jump: return .jump()
        case .celebrate: return .celebrate()
        case .shake: return .errorShake()
        case .peek: return .peek()
        case .fall: return .fall()
        }
    }

    static func ambientLoop(for ambient: CharacterAmbientAnimation) -> AmbientLoop {
        switch ambient {
        case .breathe: return .breathe
        case .blink: return .breathe  // blinking is face-driven; body breathes
        case .sleep: return .sleep
        case .bounce: return .bounce
        }
    }

    /// States whose face leaves room for a wandering gaze (errored/sleepy
    /// keep their fixed expressive look).
    static func stateHasFreeGaze(_ state: CharacterState) -> Bool {
        switch state {
        case .idle, .working, .thinking, .waiting, .happy: return true
        case .sleepy, .errored: return false
        }
    }

    static func randomGaze() -> CGSize {
        // Occasionally rest centered — glances feel intentional.
        if Double.random(in: 0...1) < 0.25 { return .zero }
        return CGSize(width: Double.random(in: -gazeAmplitude.width...gazeAmplitude.width),
                      height: Double.random(in: -gazeAmplitude.height...gazeAmplitude.height))
    }

    private func refreshGazeIfNeeded(at now: TimeInterval) {
        guard now >= nextGazeAt else { return }
        gazeFrom = currentGaze(at: now)
        gazeTarget = Self.randomGaze()
        gazeStart = now
        nextGazeAt = now + TimeInterval.random(in: Self.gazeInterval)
    }

    private func currentGaze(at now: TimeInterval) -> CGSize {
        let t = min(1, max(0, (now - gazeStart) / 0.45))
        let p = CharacterEasing.inOut.apply(CGFloat(t))
        return CGSize(width: gazeFrom.width + (gazeTarget.width - gazeFrom.width) * p,
                      height: gazeFrom.height + (gazeTarget.height - gazeFrom.height) * p)
    }

    /// Reduced-motion damping: strong clamps on movement/deformation while
    /// keeping the state legible (breathing barely visible, no hops).
    static func damped(_ deformation: CharacterDeformation) -> CharacterDeformation {
        var d = deformation
        d.offsetY = d.offsetY == 0 ? 0 : (d.offsetY < 0 ? max(d.offsetY, -0.04) : min(d.offsetY, 0.04))
        d.offsetX = d.offsetX == 0 ? 0 : (d.offsetX < 0 ? max(d.offsetX, -0.02) : min(d.offsetX, 0.02))
        d.scaleX = 1 + (d.scaleX - 1) * 0.25
        d.scaleY = 1 + (d.scaleY - 1) * 0.25
        d.lean *= 0.3
        return d
    }
}
