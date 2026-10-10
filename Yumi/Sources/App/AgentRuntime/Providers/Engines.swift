import Foundation

/// The models Yumi can think with. Each one is only a `LLMProvider`: whichever plans, the plan
/// goes through `PlanValidator`, the registry, `PermissionManager`, the executor and the
/// verification, and whichever chats, the chat has no tool that changes the Mac.
enum Engine: String, CaseIterable, Codable, Sendable {
    case claudeCode, anthropic, openai, gemini, ollama, antigravity, apple

    var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .anthropic: loc("Anthropic (clé API)")
        case .openai: loc("OpenAI (clé API)")
        case .gemini: loc("Google Gemini (clé API)")
        case .ollama: loc("Ollama (sur ce Mac)")
        case .antigravity: loc("Antigravity (compte Google)")
        case .apple: loc("Apple Intelligence (sur ce Mac)")
        }
    }

    /// Where its key lives in the Keychain, for the engines that need one.
    var keychainKey: String? {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .openai: "openai-api-key"
        case .gemini: "gemini-api-key"
        case .claudeCode, .ollama, .apple, .antigravity: nil
        }
    }

    /// The model used when the person did not choose one. Ollama has none: it uses one installed.
    var defaultModel: String? {
        switch self {
        case .anthropic: "claude-sonnet-4-6"
        case .openai: OpenAILLMProvider.defaultModel
        case .gemini: GeminiLLMProvider.defaultModel
        case .antigravity: AntigravityLLMProvider.defaultModel
        case .claudeCode, .ollama, .apple: nil
        }
    }

    /// What leaves the Mac, and who bills it. Shown in the settings, as written in the README.
    var disclosure: String {
        switch self {
        case .claudeCode: loc("Tes messages et les demandes de plan partent chez Anthropic par ton Claude Code, sous ton compte (abonnement ou facturation de ce compte).")
        case .anthropic: loc("Tes messages et les demandes de plan partent chez Anthropic. Facturé par Anthropic à l'usage.")
        case .openai: loc("Tes messages et les demandes de plan partent chez OpenAI. Facturé par OpenAI à l'usage.")
        case .gemini: loc("Tes messages et les demandes de plan partent chez Google. Le palier gratuit suffit pour essayer ; au-delà, facturé par Google.")
        case .ollama: loc("Rien ne quitte ton Mac : le modèle tourne en local. Gratuit.")
        case .antigravity: loc("Tes messages partent chez Google par ton Antigravity, sous ton compte Google (ton abonnement Gemini). Il tourne en lecture seule : il peut chercher sur le web, il ne modifie rien.")
        case .apple: loc("Rien ne quitte ton Mac : le modèle d'Apple Intelligence tourne en local, sans internet. Gratuit. Petit modèle : il comprend les demandes simples.")
        }
    }
}

/// Which engine Yumi uses, and in which order it tries the others. Stored in the defaults; the
/// keys are in the Keychain.
struct EngineSettings: Equatable, Sendable {
    static let choiceKey = "engine.choice"
    static let orderKey = "engine.order"
    static let modelKeyPrefix = "engine.model."

    /// nil: automatic, the first that answers in `order`.
    var choice: Engine?
    var order: [Engine] = Engine.allCases
    var models: [Engine: String] = [:]

    /// The engines to try, in order: the chosen one alone, or the whole order.
    var sequence: [Engine] { choice.map { [$0] } ?? Self.normalised(order) }

    func model(_ engine: Engine) -> String? { models[engine]?.nonEmptyTrimmed ?? engine.defaultModel }

    /// Every engine once, those missing at the end in the default order.
    static func normalised(_ order: [Engine]) -> [Engine] {
        var seen: [Engine] = []
        for engine in order + Engine.allCases where !seen.contains(engine) { seen.append(engine) }
        return seen
    }

    static func load(from defaults: UserDefaults = .standard) -> EngineSettings {
        var settings = EngineSettings()
        settings.choice = defaults.string(forKey: choiceKey).flatMap(Engine.init(rawValue:))
        if let raw = defaults.stringArray(forKey: orderKey) { settings.order = normalised(raw.compactMap(Engine.init(rawValue:))) }
        for engine in Engine.allCases {
            if let model = defaults.string(forKey: modelKeyPrefix + engine.rawValue) { settings.models[engine] = model }
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(choice?.rawValue, forKey: Self.choiceKey)
        defaults.set(Self.normalised(order).map(\.rawValue), forKey: Self.orderKey)
        for engine in Engine.allCases {
            defaults.set(models[engine]?.nonEmptyTrimmed, forKey: Self.modelKeyPrefix + engine.rawValue)
        }
    }
}

/// What can be known about an engine without spending anything: installed, a key present,
/// Ollama answering with a model. Whether a key is accepted is what the « Tester » button checks.
struct EngineStatus: Equatable, Sendable {
    var engine: Engine
    var ready: Bool
    var detail: String
}

enum EngineDetector {
    static func status(of engine: Engine, claudeCodeInstalled: Bool, hasKey: (Engine) -> Bool,
                       ollamaModels: [String]?, ollamaModel: String?) -> EngineStatus {
        switch engine {
        case .claudeCode:
            return claudeCodeInstalled
                ? EngineStatus(engine: engine, ready: true, detail: loc("Installé. La connexion se vérifie avec « Tester »."))
                : EngineStatus(engine: engine, ready: false, detail: loc("Pas installé."))
        case .anthropic, .openai, .gemini:
            return hasKey(engine)
                ? EngineStatus(engine: engine, ready: true, detail: loc("Clé enregistrée."))
                : EngineStatus(engine: engine, ready: false, detail: loc("Pas de clé."))
        case .ollama:
            guard let models = ollamaModels else { return EngineStatus(engine: engine, ready: false, detail: loc("Ollama ne répond pas.")) }
            guard !models.isEmpty else { return EngineStatus(engine: engine, ready: false, detail: loc("Aucun modèle installé dans Ollama.")) }
            guard let chosen = ollamaModel?.nonEmptyTrimmed else { return EngineStatus(engine: engine, ready: false, detail: loc("Choisis un modèle.")) }
            return models.contains(chosen)
                ? EngineStatus(engine: engine, ready: true, detail: loc("Modèle \(chosen)."))
                : EngineStatus(engine: engine, ready: false, detail: loc("\(chosen) n'est pas installé dans Ollama."))
        case .antigravity:
            return AntigravityLLMProvider.find() != nil
                ? EngineStatus(engine: engine, ready: true, detail: loc("Installé. La connexion se vérifie avec « Tester »."))
                : EngineStatus(engine: engine, ready: false, detail: loc("Pas installé (curl -fsSL https://antigravity.google/cli/install.sh | bash)."))
        case .apple:
            return AppleLLMProvider.isAvailable
                ? EngineStatus(engine: engine, ready: true, detail: loc("Prêt, sur ce Mac."))
                : EngineStatus(engine: engine, ready: false, detail: loc("Il faut macOS 26 et Apple Intelligence activé."))
        }
    }

    /// The model to preselect for Ollama: the one chosen if still installed, otherwise the first.
    static func ollamaModel(chosen: String?, installed: [String]) -> String? {
        if let chosen = chosen?.nonEmptyTrimmed, installed.contains(chosen) { return chosen }
        return installed.first
    }
}

/// The provider the runtime holds for its whole life. At each request it reads the settings and
/// asks the engines in order, so a change in the settings applies to the next request.
struct EngineLLMProvider: LLMProvider {
    var settings: @Sendable () -> EngineSettings
    /// The provider of an engine, nil when this build cannot use it (Claude Code on the App Store).
    var make: @Sendable (Engine, EngineSettings) -> (any LLMProvider)?

    var name: String {
        let current = settings()
        return current.choice.map { "engine:\($0.rawValue)" } ?? "engine:auto"
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let current = settings()
        let providers = current.sequence.compactMap { make($0, current) }
        return try await FallbackLLMProvider(providers: providers).complete(request)
    }
}
