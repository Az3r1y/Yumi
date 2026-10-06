import SwiftUI

/// Settings, section Moteurs: which engine Yumi thinks with, the order it tries them in, keys,
/// models, a test per engine, and what leaves the Mac with each one.
struct EnginesSettingsView: View {
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Le moteur pense pour Yumi : il discute dans le chat et propose les plans. Quel qu'il soit, chaque plan est vérifié et rien ne touche ton Mac sans ton accord.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Moteur", selection: Binding(get: { settings.choice?.rawValue ?? "auto" },
                                                set: { settings.choice = Engine(rawValue: $0); save() })) {
                Text("Automatique (le premier prêt, dans l'ordre)").tag("auto")
                ForEach(engines, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }

            ForEach(Array(EngineSettings.normalised(settings.order).filter(engines.contains).enumerated()), id: \.element) { index, engine in
                row(engine, index: index)
                Divider()
            }
        }
        .padding(6)
        .task { await refreshOllama() }
    }

    @ViewBuilder
    private func row(_ engine: Engine, index: Int) -> some View {
        let status = EngineDetector.status(of: engine, claudeCodeInstalled: EngineFactory.hasClaudeCode,
                                           hasKey: { !(keys[$0] ?? "").isEmpty && KeychainStore.shared.get($0.keychainKey ?? "") != nil },
                                           ollamaModels: ollamaModels, ollamaModel: settings.models[.ollama])
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(index + 1). \(engine.label)").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { move(engine, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).buttonStyle(.borderless)
                Button { move(engine, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
            }
            Text(status.detail).font(.system(size: 11)).foregroundColor(status.ready ? .green : .secondary)
            if let key = engine.keychainKey {
                HStack {
                    SecureField("Clé API", text: Binding(get: { keys[engine] ?? "" }, set: { keys[engine] = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Enregistrer") {
                        let value = (keys[engine] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.isEmpty { KeychainStore.shared.remove(key) } else { KeychainStore.shared.set(key, value: value) }
                        results[engine] = value.isEmpty ? "Clé retirée." : "Clé enregistrée."
                    }
                }
            }
            if engine.defaultModel != nil {
                TextField("Modèle (\(engine.defaultModel ?? ""))", text: Binding(get: { settings.models[engine] ?? "" },
                                                                                  set: { settings.models[engine] = $0; save() }))
                    .textFieldStyle(.roundedBorder)
            }
            if engine == .ollama, let models = ollamaModels, !models.isEmpty {
                Picker("Modèle", selection: Binding(get: { settings.models[.ollama] ?? "" },
                                                    set: { settings.models[.ollama] = $0; save() })) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            }
            Text(engine.disclosure).font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(testing.contains(engine) ? "Test…" : "Tester") { test(engine) }
                    .disabled(testing.contains(engine))
                if engine == .ollama { Button("Actualiser") { Task { await refreshOllama() } } }
                if let result = results[engine] { Text(result).font(.system(size: 11)) }
            }
        }
    }

    private func save() { settings.save() }

    private func move(_ engine: Engine, by offset: Int) {
        var order = EngineSettings.normalised(settings.order)
        guard let index = order.firstIndex(of: engine), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        settings.order = order
        save()
    }

    private func test(_ engine: Engine) {
        testing.insert(engine)
        Task {
            let result = await EngineFactory.test(engine)
            results[engine] = result
            testing.remove(engine)
        }
    }

    private func refreshOllama() async {
        let models = await OllamaLLMProvider.installedModels()
        ollamaModels = models
        if let models, let model = EngineDetector.ollamaModel(chosen: settings.models[.ollama], installed: models),
           model != settings.models[.ollama] {
            settings.models[.ollama] = model
            save()
        }
    }
}
