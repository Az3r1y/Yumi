import SwiftUI

/// Scripted 4.6 s greeting for the character, built on the Character System:
/// grow-in (back ease), a pop hop at 1.36 s, two blinks, all through the same
/// renderer the notch uses. Timeline runs once per `runID`.
struct GreetingCanvasView: View {
    /// Incremented each time the greeting starts; restarts the timeline.
    let runID: Int

    /// Greeting timeline (seconds).
    private enum T {
        static let grow = 0.45
        static let pop0 = 1.36
        static let pop1 = 1.52
        static let end = 4.60
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startDate)
                guard t >= 0 else { return }
                draw(at: min(t, T.end + 0.4), in: context, size: size)
            }
        }
        .onChange(of: runID) { _, _ in
            restart()
        }
        .onAppear {
            restart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            completionTask?.cancel()
            completionTask = nil
        }
    }

    /// Real clock captured when the greeting starts — the timeline restarts
    /// from it on each new run.
    @State private var startDate: Date = .now
    @State private var completionTask: Task<Void, Never>?

    private func restart() {
        startDate = .now
        scheduleCompletion()
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(T.end))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .greetComplete, object: nil)
        }
    }

    // MARK: - Drawing

    private func draw(at t: Double, in context: GraphicsContext, size: CGSize) {
        // Grow in with a back ease (slight overshoot → settle).
        let growT = max(0, min(1, t / T.grow))
        let scale = 0.05 + 0.95 * CharacterEasing.back.apply(CGFloat(growT))

        // Pop: a little hop at 1.36–1.52 s.
        let popT = max(0, min(1, (t - T.pop0) / (T.pop1 - T.pop0)))
        let hopRadius = -sin(popT * .pi) * 0.22  // in body radii

        let deformation = CharacterDeformation(
            scaleX: scale, scaleY: scale,
            offsetY: hopRadius,
            grounded: 0,
            eyeSquashResistance: 0.6)

        // Face: happy, with two scripted blinks (0.55 s and 1.50 s).
        var face = CharacterFace.happy
        face.eyeOpenness = blinkOpenness(at: t)

        let pose = CharacterPose(
            state: .happy,
            face: face,
            deformation: deformation,
            time: t,
            anchor: startDate.timeIntervalSinceReferenceDate)

        // Draw the character centered in the island.
        var characterContext = context
        characterContext.translateBy(x: size.width / 2, y: size.height / 2 + 4)
        let characterSize = CGSize(width: 120, height: 120)
        YumiCharacterRenderer.draw(pose: pose, in: &characterContext, size: characterSize)
    }

    /// Double blink during the greeting (0.55 s and 1.50 s).
    private func blinkOpenness(at t: Double) -> CGFloat {
        for blinkTime in [0.55, 1.50] {
            let bt = (t - blinkTime) / 0.2
            if bt >= 0 && bt <= 1 {
                return 1 - sin(bt * .pi)
            }
        }
        return 1
    }
}
