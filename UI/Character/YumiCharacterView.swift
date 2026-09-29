import SwiftUI

/// The Yumi character view. Usable standalone:
///
///     YumiCharacterView(state: .idle)          // fixed state
///     YumiCharacterView(controller: controller) // live, app-driven
///
/// TimelineView(.animation) only runs while the view is visible (SwiftUI
/// pauses it off-screen), so an hidden character costs nothing.
struct YumiCharacterView: View {
    private var controller: CharacterAnimationController?
    private var fixedState: CharacterState
    private var fixedFace: CharacterFace?

    /// Live mode: driven by a CharacterAnimationController.
    init(controller: CharacterAnimationController) {
        self.controller = controller
        self.fixedState = .idle
        self.fixedFace = nil
    }

    /// Static mode: a fixed state (previews, tests, simple integrations).
    init(state: CharacterState) {
        self.controller = nil
        self.fixedState = state
        self.fixedFace = nil
    }

    /// Static mode with an explicit face override (expression designer).
    init(face: CharacterFace) {
        self.controller = nil
        self.fixedState = .idle
        self.fixedFace = face
    }

    var body: some View {
        if let controller {
            TimelineView(.animation) { _ in
                Canvas { context, size in
                    // One clock everywhere: systemUptime (matches the
                    // controller's anchors). TimelineView just provides the
                    // display-rate ticking and pauses off-screen.
                    let pose = controller.pose(at: ProcessInfo.processInfo.systemUptime)
                    var mutable = context
                    Self.draw(pose: pose, size: size, into: &mutable)
                }
            }
        } else {
            StaticCharacterView(state: fixedState, faceOverride: fixedFace)
        }
    }

    /// Applies the blink to the pose, then renders. Factored so both modes
    /// share the exact same drawing path.
    static func draw(pose: CharacterPose, size: CGSize, into context: inout GraphicsContext) {
        var face = pose.face
        face.eyeOpenness *= CharacterEyeAnimation.openness(
            at: pose.time, anchor: pose.anchor)
        var posed = pose
        posed.face = face
        YumiCharacterRenderer.draw(pose: posed, in: &context, size: size)
    }
}

// MARK: - Static mode

private struct StaticCharacterView: View {
    let state: CharacterState
    let faceOverride: CharacterFace?

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let now = ProcessInfo.processInfo.systemUptime
                let ambient = AmbientLoop.breathe.sample(at: now - anchor)
                let face = faceOverride ?? state.face
                let posed = CharacterPose(
                    state: state,
                    face: face,
                    deformation: CharacterDeformation.identity.combined(with: ambient),
                    time: now,
                    anchor: anchor)
                var mutable = context
                YumiCharacterRenderer.draw(pose: posed, in: &mutable, size: size)
            }
        }
    }

    // A stable anchor per view instance.
    @State private var anchor: TimeInterval = ProcessInfo.processInfo.systemUptime
}
