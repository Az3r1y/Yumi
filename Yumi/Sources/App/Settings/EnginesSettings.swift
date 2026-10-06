import SwiftUI

/// Moteurs: the presentation of the engine settings. The logic is the one of the engines
/// (EngineSettings, EngineDetector, EngineFactory), unchanged: same choice, same order, same
/// keys, same models, same test.
struct EnginesSettings: View {
    @State private var settings = EngineSettings.load()
    @State private var keys: [Engine: String] = Dictionary(uniqueKeysWithValues: Engine.allCases.compactMap { engine in
        engine.keychainKey.map { (engine, KeychainStore.shared.get($0) ?? "") }
    })
    @State private var ollamaModels: [String]? = nil
    @State private var results: [Engine: String] = [:]
    @State private var testing: Set<Engine> = []

    private var engines: [Engine] {
        #if APPSTORE
        Engine.allCases.filter { $0 != .claudeCode }
        #else
        Engine.allCases
        #endif
    }

    var body: some View {
        let order = EngineSettings.normalised(settings.order).filter(engines.contains)
        Form {
            Section {
                Picker("Moteur", selection: Binding(get: { settings.choice?.rawValue ?? "auto" },
                                                    set: { settings.choice = Engine(rawValue: $0); settings.save() })) {
                    Text("Automatique").tag("auto")
                    ForEach(engines, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            } footer: {
                SettingsHelp("Le moteur pense pour moi : il discute dans le chat et propose les plans. Quel qu'il soit, chaque plan est vérifié, et rien ne touche ton Mac sans ton accord. En automatique, je prends le premier prêt, dans l'ordre ci-dessous.")
            }

            ForEach(Array(order.enumerated()), id: \.element) { index, engine in
                section(engine, index: index, last: index == order.count - 1)
            }
        }
        .task { await refreshOllama() }
    }

    @ViewBuilder
    private func section(_ engine: Engine, index: Int, last: Bool) -> some View {
        let status = EngineDetector.status(of: engine, claudeCodeInstalled: EngineFactory.hasClaudeCode,
                                           hasKey: { !(keys[$0] ?? "").isEmpty && KeychainStore.shared.get($0.keychainKey ?? "") != nil },
                                           ollamaModels: ollamaModels, ollamaModel: settings.models[.ollama])
        Section {
            LabeledContent("État") {
                SettingsStatus(text: status.detail, tone: status.ready ? .ok : .off)
            }
            if let key = engine.keychainKey {
                LabeledContent("Clé API") {
                    HStack {
                        SecureField("", text: Binding(get: { keys[engine] ?? "" }, set: { keys[engine] = $0 }))
                            .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        Button("Enregistrer") {
                            let value = (keys[engine] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if value.isEmpty { KeychainStore.shared.remove(key) } else { KeychainStore.shared.set(key, value: value) }
                            results[engine] = value.isEmpty ? "Clé retirée." : "Clé enregistrée."
                        }
                    }
                }
            }
            if engine == .ollama, let models = ollamaModels, !models.isEmpty {
                Picker("Modèle", selection: Binding(get: { settings.models[.ollama] ?? "" },
                                                    set: { settings.models[.ollama] = $0; settings.save() })) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            } else if let model = engine.defaultModel {
                LabeledContent("Modèle") {
                    TextField("", text: Binding(get: { settings.models[engine] ?? "" },
                                                set: { settings.models[engine] = $0; settings.save() }),
                              prompt: Text(model))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
            }
            HStack {
                Button(testing.contains(engine) ? "Test en cours…" : "Tester") { test(engine) }
                    .disabled(testing.contains(engine))
                if engine == .ollama { Button("Actualiser les modèles") { Task { await refreshOllama() } } }
                if let result = results[engine] {
                    Text(result).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } header: {
            HStack {
                Text("\(index + 1). \(engine.label)")
                Spacer()
                Button { move(engine, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .help("Essayer plus tôt")
                Button { move(engine, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(last)
                    .help("Essayer plus tard")
            }
        } footer: {
            SettingsHelp(engine.disclosure)
        }
    }

    private func move(_ engine: Engine, by offset: Int) {
        var order = EngineSettings.normalised(settings.order)
        guard let index = order.firstIndex(of: engine), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        settings.order = order
        settings.save()
    }

    private func test(_ engine: Engine) {
        testing.insert(engine)
        Task {
            results[engine] = await EngineFactory.test(engine)
            testing.remove(engine)
        }
    }

    private func refreshOllama() async {
        let models = await OllamaLLMProvider.installedModels()
        ollamaModels = models
        if let models, let model = EngineDetector.ollamaModel(chosen: settings.models[.ollama], installed: models),
           model != settings.models[.ollama] {
            settings.models[.ollama] = model
            settings.save()
        }
    }
}
