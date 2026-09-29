import Testing
import Foundation
import CoreGraphics
@testable import Yumi

// MARK: - Reactions

@Suite struct CharacterReactionTests {

    @Test func reactionExpiresAndReturnsToBaseState() {
        let reaction = CharacterReaction(kind: .celebrate, startedAt: 10, duration: 1.6)
        #expect(reaction.isActive(at: 11.5))
        #expect(!reaction.isActive(at: 11.6))
        #expect(!reaction.isActive(at: 12.0))
    }

    @Test func reactionProgressBounds() {
        let reaction = CharacterReaction(kind: .error, startedAt: 0, duration: 1.0)
        #expect(reaction.progress(at: -5) == 0)
        #expect(reaction.progress(at: 0.5) == 0.5)
        #expect(reaction.progress(at: 2.0) == 1)
    }

    @Test func errorHasHighestPriority() {
        let celebrate = CharacterReaction(kind: .celebrate, startedAt: 0)
        let error = CharacterReaction(kind: .error, startedAt: 0)
        let surprise = CharacterReaction(kind: .surprise, startedAt: 0)
        let attention = CharacterReaction(kind: .attention, startedAt: 0)
        #expect(error.priority > surprise.priority)
        #expect(surprise.priority > celebrate.priority)
        #expect(celebrate.priority > attention.priority)
    }
}

// MARK: - Animation controller (reactions & reduced motion)

@MainActor
@Suite struct CharacterAnimationControllerTests {

    @Test func reactionOverridesStateFaceThenExpires() {
        let controller = CharacterAnimationController()
        controller.setState(.working)
        let t0: TimeInterval = 100

        controller.playReaction(.celebrate, at: t0)

        // During the reaction: excited face + celebration deformation.
        let mid = controller.pose(at: t0 + 0.3)
        #expect(mid.face == CharacterFace.excited)
        #expect(mid.state == .working)  // the state itself never changes
        #expect(mid.deformation != .identity)

        // After expiry: back to the state's resting face.
        let after = controller.pose(at: t0 + 3.0)
        #expect(after.face == .focused)  // .working's face
    }

    @Test func higherPriorityReactionReplacesLower() {
        let controller = CharacterAnimationController()
        let t0: TimeInterval = 100

        controller.playReaction(.celebrate, at: t0)
        controller.playReaction(.error, at: t0 + 0.2)

        let pose = controller.pose(at: t0 + 0.5)
        #expect(pose.face == .worried)  // error reaction won
    }

    @Test func lowerPriorityReactionIsIgnoredWhileHigherActive() {
        let controller = CharacterAnimationController()
        let t0: TimeInterval = 100

        controller.playReaction(.error, at: t0)
        controller.playReaction(.celebrate, at: t0 + 0.2)

        let pose = controller.pose(at: t0 + 0.5)
        #expect(pose.face == .worried)  // celebrate did not replace error
    }

    @Test func reducedMotionDampsMotionButKeepsIdentity() {
        let hop = CharacterDeformation.hop(height: 0.9)
        let damped = CharacterAnimationController.damped(hop)
        #expect(abs(damped.offsetY) < abs(hop.offsetY))
        #expect(damped.scaleX == 1)
        #expect(damped.scaleY == 1)

        let squash = CharacterDeformation.squash(amount: 0.2)
        let dampedSquash = CharacterAnimationController.damped(squash)
        #expect(abs(dampedSquash.scaleX - 1) < abs(squash.scaleX - 1))
        #expect(abs(dampedSquash.scaleY - 1) < abs(squash.scaleY - 1))
    }

    @Test func reducedMotionKeepsStateLegible() {
        // With reduced motion, ambient breathing is damped but not removed:
        // the pose is still distinguishable from a frozen body.
        let breathe = AmbientLoop.breathe.sample(at: 2.6)  // mid-squash phase
        let damped = CharacterAnimationController.damped(breathe)
        #expect(damped.scaleY != 1 || damped.scaleX != 1)
    }
}

// MARK: - Animation primitives

@Suite struct CharacterAnimationTests {

    @Test func easingStaysWithinBounds() {
        for ease in [CharacterEasing.linear, .inOut, .out, .back] {
            #expect(ease.apply(-1) >= -1e-12)
            #expect(abs(ease.apply(0)) < 1e-12)   // floating-point epsilon at boundaries
            #expect(abs(ease.apply(1) - 1) < 1e-12)
            #expect(ease.apply(2) <= 1.2)  // back overshoots slightly, others clamp
        }
    }

    @Test func celebrationSequenceStartsSquashedAndEndsAtRest() {
        let animation = CharacterAnimation.celebrate()
        #expect(animation.sample(at: 0.06).scaleY < 1)   // anticipation squash
        #expect(animation.sample(at: animation.duration).isIdentity)
    }

    @Test func shakeEndsAtRest() {
        let animation = CharacterAnimation.errorShake()
        #expect(animation.sample(at: animation.duration).isIdentity)
    }

    @Test func ambientLoopCycles() {
        let loop = AmbientLoop.bounce
        let period = loop.period
        #expect(loop.sample(at: 0.1).scaleY == loop.sample(at: period + 0.1).scaleY)
    }

    @Test func deformationInterpolationIsLinear() {
        let a = CharacterDeformation.identity
        let b = CharacterDeformation.squash(amount: 0.5)
        let mid = a.interpolated(to: b, t: 0.5)
        #expect(abs(mid.scaleX - 1.25) < 0.0001)
        #expect(abs(mid.scaleY - 0.75) < 0.0001)
    }

    @Test func combiningDeformationsAccumulates() {
        let hop = CharacterDeformation.hop(height: 0.5)
        let lean = CharacterDeformation.lean(angle: 0.1)
        let combined = hop.combined(with: lean)
        #expect(combined.offsetY == -0.5)
        #expect(combined.lean == 0.1)
    }
}

// MARK: - Faces & blinks

@Suite struct CharacterFaceTests {

    @Test func allExpressionFacesAreDistinct() {
        let faces: [CharacterFace] = [.idle, .sleepy, .curious, .focused, .thinking,
                                      .happy, .excited, .worried, .confused, .annoyed,
                                      .surprised, .panicked]
        #expect(Set(faces).count == faces.count)
    }

    @Test func everyCharacterStateHasFaceAndAmbient() {
        for state in CharacterState.allCases {
            // Compiles & returns: the exhaustiveness contract.
            _ = state.face
            _ = state.ambient
        }
    }

    @Test func blinkIsDeterministicAndClosedOnlyBriefly() {
        let anchor: TimeInterval = 42
        // Same input → same output.
        #expect(CharacterEyeAnimation.openness(at: 10, anchor: anchor)
                == CharacterEyeAnimation.openness(at: 10, anchor: anchor))

        // Eyes are open most of the time: sample 200 points, closed must be rare.
        let closedCount = (0..<200).filter { i in
            CharacterEyeAnimation.openness(at: Double(i) * 0.05, anchor: anchor) < 0.5
        }.count
        #expect(closedCount < 20)
    }
}
