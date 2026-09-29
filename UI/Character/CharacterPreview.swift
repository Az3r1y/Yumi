import SwiftUI

/// Developer/designer tool: every expression, deformation and animation of
/// the character on one screen, at several sizes. Also used as the interactive
/// designer window (menu: Settings → "Character designer…").
struct CharacterPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Expressions") {
                    ForEach(Array(expressionFaces.sorted(by: { $0.key < $1.key })), id: \.key) { name, face in
                        VStack(spacing: 4) {
                            YumiCharacterView(face: face)
                                .frame(width: 84, height: 84)
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                section("Sizes (idle)") {
                    HStack(alignment: .bottom, spacing: 20) {
                        ForEach([24, 32, 48, 64, 96, 128], id: \.self) { size in
                            VStack(spacing: 4) {
                                YumiCharacterView(state: .idle)
                                    .frame(width: CGFloat(size), height: CGFloat(size))
                                Text("\(size)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                section("States (live ambient animations)") {
                    HStack(spacing: 16) {
                        ForEach(CharacterState.allCases, id: \.self) { state in
                            VStack(spacing: 4) {
                                YumiCharacterView(state: state)
                                    .frame(width: 72, height: 72)
                                Text("\(state)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                section("One-shot animations") {
                    HStack(spacing: 16) {
                        ForEach(CharacterOneShotAnimation.allCases, id: \.self) { shot in
                            VStack(spacing: 4) {
                                AnimationLoopView(oneShot: shot)
                                    .frame(width: 72, height: 72)
                                Text("\(shot)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                section("Reactions") {
                    HStack(spacing: 16) {
                        ForEach(Array(reactionKinds.sorted(by: { $0.key < $1.key })), id: \.key) { name, kind in
                            VStack(spacing: 4) {
                                ReactionLoopView(kind: kind)
                                    .frame(width: 72, height: 72)
                                Text(name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 760, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Data

    private var expressionFaces: [String: CharacterFace] {
        ["idle": .idle, "sleepy": .sleepy, "curious": .curious, "focused": .focused,
         "thinking": .thinking, "happy": .happy, "excited": .excited, "worried": .worried,
         "confused": .confused, "annoyed": .annoyed, "surprised": .surprised, "panicked": .panicked]
    }

    private var reactionKinds: [String: CharacterReaction.Kind] {
        ["celebrate": .celebrate, "error": .error, "surprise": .surprise, "attention": .attention]
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}

// MARK: - Looping animation samples (preview only)

/// Replays a one-shot animation forever (designer tool only).
private struct AnimationLoopView: View {
    let oneShot: CharacterOneShotAnimation

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let now = ProcessInfo.processInfo.systemUptime
                let animation = CharacterAnimationController.animation(for: oneShot)
                let phase = now.truncatingRemainder(dividingBy: animation.duration + 0.4)
                let deformation = animation.sample(at: phase)
                let pose = CharacterPose(state: .idle, face: .idle,
                                         deformation: deformation,
                                         time: now, anchor: now)
                var mutable = context
                YumiCharacterRenderer.draw(pose: pose, in: &mutable, size: size)
            }
        }
    }
}

/// Replays a reaction forever (designer tool only).
private struct ReactionLoopView: View {
    let kind: CharacterReaction.Kind

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let now = ProcessInfo.processInfo.systemUptime
                let reaction = CharacterReaction(kind: kind, startedAt: 0)
                let animation = reaction.bodyAnimation
                let phase = now.truncatingRemainder(dividingBy: animation.duration + 0.8)
                let deformation = animation.sample(at: phase)
                let pose = CharacterPose(state: .idle, face: reaction.face,
                                         deformation: deformation,
                                         time: now, anchor: now)
                var mutable = context
                YumiCharacterRenderer.draw(pose: pose, in: &mutable, size: size)
            }
        }
    }
}

#Preview {
    CharacterPreview()
}
