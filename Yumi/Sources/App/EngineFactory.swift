import Foundation

/// Builds each engine's provider for this build, with the keys of the Keychain. Used by the
/// agent (planning) and the chat (conversation without tools).
enum EngineFactory {
    static func provider(_ engine: Engine, _ settings: EngineSettings) -> (any LLMProvider)? {
        switch engine {
        case .claudeCode:
            #if APPSTORE
            return nil // The App Store build may not launch programs.
            #else
            return ClaudeCodeLLMProvider(binary: { ClaudeCLI.find() },
                                         folder: AppIdentity.supportDirectory.appendingPathComponent("planner").path,
                                         model: settings.models[.claudeCode]?.nonEmptyTrimmed)
            #endif
        case .anthropic:
            return AnthropicLLMProvider(model: settings.model(.anthropic) ?? "claude-sonnet-4-6", apiKey: key(.anthropic))
        case .openai:
            return OpenAILLMProvider(model: settings.model(.openai) ?? OpenAILLMProvider.defaultModel, apiKey: key(.openai))
        case .gemini:
            return GeminiLLMProvider(model: settings.model(.gemini) ?? GeminiLLMProvider.defaultModel, apiKey: key(.gemini),
                                     remember: { model in
                                         // Shown in the settings, where the person can change it.
                                         var saved = EngineSettings.load()
                                         saved.models[.gemini] = model
                                         saved.save()
                                     })
        case .ollama:
            let model = settings.models[.ollama]
            return OllamaLLMProvider(model: { model })
        case .antigravity:
            #if APPSTORE
            return nil // The App Store build may not launch programs.
            #else
            return AntigravityLLMProvider(folder: AppIdentity.supportDirectory.appendingPathComponent("antigravity").path,
                                          model: settings.model(.antigravity), isOwnHooks: { AntigravityHooks.isOwn($0) })
            #endif
        case .apple:
            return AppleLLMProvider()
        }
    }

    static func key(_ engine: Engine) -> @Sendable () -> String? {
        { engine.keychainKey.flatMap { KeychainStore.shared.get($0) } }
    }

    static var hasClaudeCode: Bool {
        #if APPSTORE
        false
        #else
        ClaudeCLI.find() != nil
        #endif
    }

    /// The runtime's provider: the settings read at each request.
    static var planner: EngineLLMProvider {
        EngineLLMProvider(settings: { EngineSettings.load() }, make: { provider($0, $1) })
    }

    /// Asks the engine one short question: "OK" when it answers, otherwise why not.
    static func test(_ engine: Engine) async -> String {
        guard let provider = provider(engine, EngineSettings.load()) else { return loc("Indisponible dans cette version.") }
        let request = LLMRequest(system: "Answer with the single word OK.", messages: [LLMMessage(role: .user, content: "Test")],
                                 expectsJSON: false, maxOutputTokens: 20)
        do {
            _ = try await provider.complete(request)
            return loc("✓ Répond.")
        } catch LLMProviderError.unavailable {
            return engine == .claudeCode ? loc("Claude Code n'est pas installé ou pas connecté (claude, puis /login).") : loc("Pas configuré.")
        } catch LLMProviderError.failed(let reason) {
            return "✗ " + ChatPhrases.engineFailed(engine.label, reason: reason)
        } catch {
            return loc("✗ Pas de réponse.")
        }
    }
}
