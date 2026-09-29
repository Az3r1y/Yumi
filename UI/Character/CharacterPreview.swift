import SwiftUI

/// Developer/designer tool for the character system. Left: a live character
/// driven by the chosen state/expression/deformation and one-shot buttons.
/// Bottom: a reference gallery (all faces at all sizes).
/// Reachable from the menu bar: "Character designer…" — no app restart needed.
struct CharacterPreview: View {
    @State private var controller = CharacterAnimationController()
    @State private var mode: Mode = .state
    @State private var selectedState: CharacterState = .idle
    @State private var selectedExpression: String = "idle"
    @State private var squash: CGFloat = 0
    @State private var stretch: CGFloat = 0
    @State private var lean: CGFloat = 0

    enum Mode: String, CaseIterable {
        case state = "State"
        case expression = "Expression"
        case deformation = "Deformation"
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: live character + controls ──
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    YumiCharacterView(controller: controller)
                        .frame(width: 190, height: 180)
                }
                .frame(width: 230, height: 210)

                Picker("Drive by", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .state:
                    Picker("State", selection: $selectedState) {
                        ForEach(CharacterState.allCases, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .onChange(of: selectedState) { _, newValue in
                        applyCurrentDrive()
                    }
                case .expression:
                    Picker("Expression", selection: $selectedExpression) {
                        ForEach(expressionFaces.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: selectedExpression) { _, _ in applyCurrentDrive() }
                case .deformation:
                    VStack(spacing: 10) {
                        slider("Squash", value: $squash)
                        slider("Stretch", value: $stretch)
                        slider("Lean", value: $lean)
                    }
                    .padding(.horizontal)
                    .onChange(of: squash) { _, _ in applyCurrentDrive() }
                    .onChange(of: stretch) { _, _ in applyCurrentDrive() }
                    .onChange(of: lean) { _, _ in applyCurrentDrive() }
                }

                // One-shot animations & reactions
                VStack(spacing: 8) {
                    Text("One-shots").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(CharacterOneShotAnimation.allCases, id: \.self) { shot in
                            Button("\(shot)") {
                                controller.playOneShot(shot, at: ProcessInfo.processInfo.systemUptime)
                                applyCurrentDrive()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("Reactions").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Array(reactionKinds.sorted(by: { $0.key < $1.key })), id: \.key) { name, kind in
                            Button(name) {
                                controller.playReaction(kind, at: ProcessInfo.processInfo.systemUptime)
                                applyCurrentDrive()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Toggle("Reduce Motion (simulate)", isOn: Binding(
                    get: { controller.reduceMotion },
                    set: { controller.setReduceMotion($0) }))
                    .padding(.horizontal)
            }
            .frame(width: 300)
            .padding(.vertical, 20)

            Divider()

            // ── Right: reference gallery ──
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    gallerySection("Expressions") {
                        ForEach(expressionFaces.keys.sorted(), id: \.self) { name in
                            galleryCell(name) {
                                YumiCharacterView(face: expressionFaces[name]!)
                                    .frame(width: 64, height: 64)
                            }
                        }
                    }
                    gallerySection("Sizes") {
                        ForEach([24, 32, 48, 64, 96, 128], id: \.self) { size in
                            galleryCell("\(size)") {
                                YumiCharacterView(state: .idle)
                                    .frame(width: CGFloat(size), height: CGFloat(size))
                            }
                        }
                    }
                    gallerySection("States") {
                        ForEach(CharacterState.allCases, id: \.self) { state in
                            galleryCell("\(state)") {
                                YumiCharacterView(state: state)
                                    .frame(width: 56, height: 56)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 880, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { applyCurrentDrive() }
    }

    // MARK: - Drive logic

    private func applyCurrentDrive() {
        switch mode {
        case .state:
            controller.setOverrides(face: nil, deformation: nil)
            controller.setState(selectedState)
        case .expression:
            controller.setOverrides(face: expressionFaces[selectedExpression], deformation: nil)
        case .deformation:
            controller.setOverrides(
                face: nil,
                deformation: CharacterDeformation(
                    scaleX: 1 + squash - stretch * 0.5,
                    scaleY: 1 - squash + stretch,
                    lean: lean,
                    offsetY: 0,
                    offsetX: 0,
                    grounded: squash > 0 ? 1 : 0,
                    eyeSquashResistance: 0.6))
        }
    }

    private func slider(_ label: String, value: Binding<CGFloat>) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 60, alignment: .leading)
            Slider(value: value, in: -0.4...0.5)
        }
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

    // MARK: - Small views

    @ViewBuilder
    private func gallerySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func galleryCell<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
                .frame(height: 70)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CharacterPreview()
}
