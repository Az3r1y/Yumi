import Foundation

/// Sends each request to the engine and the model that suit it: a quick question to a small
/// model, code to Sonnet, a long reasoning to Opus, the web and design to Gemini. The routes are
/// the person's (Réglages › Moteurs); whatever answers, plans go through the same checks.
enum TaskRouter {
    enum Kind: String, CaseIterable, Sendable {
        case simple, code, reasoning, web, creative

        var label: String {
            switch self {
            case .simple: loc("Simple")
            case .code: loc("Code")
            case .reasoning: loc("Raisonnement long")
            case .web: loc("Web, actualité")
            case .creative: loc("Design, créatif")
            }
        }
    }

    struct Route: Equatable, Hashable, Sendable {
        var engine: Engine
        /// nil: the engine's model of the settings.
        var model: String?

        /// "claudeCode|haiku": how it is saved.
        var stored: String { engine.rawValue + "|" + (model ?? "") }
        init(engine: Engine, model: String?) { self.engine = engine; self.model = model }
        init?(stored: String) {
            let parts = stored.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let engine = parts.first.flatMap({ Engine(rawValue: String($0)) }) else { return nil }
            self.init(engine: engine, model: parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil)
        }

        /// "Claude Haiku", "Gemini 3.1 Pro": what the island says after "via".
        var label: String {
            Self.choices.first { $0.route == self }?.label ?? (model ?? engine.label)
        }

        /// The routes offered in the settings and by `@name` in a message.
        static let choices: [(route: Route, label: String, names: [String])] = [
            (Route(engine: .claudeCode, model: "haiku"), "Claude Haiku", ["haiku"]),
            (Route(engine: .claudeCode, model: "sonnet"), "Claude Sonnet", ["sonnet", "claude"]),
            (Route(engine: .claudeCode, model: "opus"), "Claude Opus", ["opus"]),
            (Route(engine: .antigravity, model: "gemini-3.8-flash-medium"), "Gemini Flash", ["flash", "gemini"]),
            (Route(engine: .antigravity, model: "gemini-3.1-pro-high"), "Gemini 3.1 Pro", ["pro"]),
            (Route(engine: .apple, model: nil), "Apple Intelligence", ["apple", "local"]),
        ]
    }

    static let defaults: [Kind: Route] = [
        .simple: Route(engine: .claudeCode, model: "haiku"),
        .code: Route(engine: .claudeCode, model: "sonnet"),
        .reasoning: Route(engine: .claudeCode, model: "opus"),
        .web: Route(engine: .antigravity, model: "gemini-3.8-flash-medium"),
        .creative: Route(engine: .antigravity, model: "gemini-3.1-pro-high"),
    ]

    /// `@opus explique…`: the route named at the start of the message, and the message without it.
    static func forced(_ message: String) -> (route: Route, message: String)? {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return nil }
        let word = trimmed.dropFirst().prefix { !$0.isWhitespace }.lowercased()
        guard let choice = Route.choices.first(where: { $0.names.contains(word) }) else { return nil }
        let rest = trimmed.dropFirst(word.count + 1).trimmingCharacters(in: .whitespaces)
        return (choice.route, rest)
    }

    /// The kind of a request by its words, or nil when they say nothing clear.
    /// ponytail: keyword rules, French and English; Apple Intelligence settles the rest (`classify`).
    static func kind(of message: String) -> Kind? {
        let text = message.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["cherche sur", "sur le web", "sur internet", "actualite", "actu ", "news", "dernieres nouvelles",
                "aujourd'hui dans le monde", "prix de", "cours de", "meteo a", "search the web", "latest", "who won", "qui a gagne"]) { return .web }
        if has(["design", "maquette", "logo", "couleur", "palette", "typo", "interface", "ui ", " ux", "mockup", "illustration",
                "slogan", "nom pour", "idees de", "creatif", "poeme", "histoire courte", "brainstorm"]) { return .creative }
        if has(["code", "swift", "python", "javascript", "typescript", "fonction", "function", "bug", "compile", "regex",
                "sql", "script", "api ", "git ", "stack trace", "refactor", "xcode", "terminal"]) { return .code }
        if message.count > 600 || has(["analyse", "compare", "strategie", "plan detaille", "pourquoi exactement", "demontre",
                                       "explique en detail", "pros and cons", "avantages et inconvenients", "step by step", "etape par etape"]) { return .reasoning }
        if message.count < 80 { return .simple }
        return nil
    }

    /// The kind of a request: its words, then Apple Intelligence on the Mac when they are not
    /// clear, then its length.
    static func classify(_ message: String, ask: (@Sendable (String) async -> String?)? = nil) async -> Kind {
        if let kind = kind(of: message) { return kind }
        if let ask, let answer = await ask(message)?.lowercased(),
           let kind = Kind.allCases.first(where: { answer.contains($0.rawValue) }) {
            return kind
        }
        return message.count > 300 ? .reasoning : .simple
    }

    static let classifierPrompt = """
        Classify the user's request into exactly one word: simple (a quick question, a reminder, small talk), \
        code (programming), reasoning (a long analysis or a complex plan), web (needs fresh information from the \
        internet), creative (design, visual, naming, writing ideas). Answer with the word only.
        """

    /// The route decided for the request being answered: the chat sets it, the planner reads it.
    @TaskLocal static var current: Route?
}

/// The router's settings: on or off, and the route of each kind.
struct RouterSettings: Equatable, Sendable {
    static let enabledKey = "router.enabled"
    static let routeKeyPrefix = "router.route."

    var enabled = true
    var routes: [TaskRouter.Kind: TaskRouter.Route] = TaskRouter.defaults

    func route(_ kind: TaskRouter.Kind) -> TaskRouter.Route { routes[kind] ?? TaskRouter.defaults[kind]! }

    static func load(from defaults: UserDefaults = .standard) -> RouterSettings {
        var settings = RouterSettings()
        if defaults.object(forKey: enabledKey) != nil { settings.enabled = defaults.bool(forKey: enabledKey) }
        for kind in TaskRouter.Kind.allCases {
            if let route = defaults.string(forKey: routeKeyPrefix + kind.rawValue).flatMap(TaskRouter.Route.init(stored:)) {
                settings.routes[kind] = route
            }
        }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        for kind in TaskRouter.Kind.allCases { defaults.set(route(kind).stored, forKey: Self.routeKeyPrefix + kind.rawValue) }
    }
}

extension EngineSettings {
    /// The engines to try for a routed request: the routed one with its model first, then the
    /// usual sequence (the routed engine again there with its own model, as a fallback).
    func routed(_ route: TaskRouter.Route?) -> [(engine: Engine, settings: EngineSettings)] {
        var tries = sequence.map { (engine: $0, settings: self) }
        guard let route else { return tries }
        var first = self
        if let model = route.model { first.models[route.engine] = model }
        tries.removeAll { $0.engine == route.engine && route.model == nil }
        return [(route.engine, first)] + tries
    }
}
