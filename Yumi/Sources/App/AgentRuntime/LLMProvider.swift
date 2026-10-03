import Foundation

/// A language model, whoever provides it (Anthropic, OpenAI, Gemini, a local model). Text in,
/// text out: the runtime builds the request and reads the answer itself, so a provider only
/// has to carry them. A provider never sees the tools' code, the policy or the permissions,
/// and nothing it answers is run without going through `PlanValidator` and the executor.
protocol LLMProvider: Sendable {
    /// Shown in the debug panel and recorded with each plan.
    var name: String { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

struct LLMRequest: Equatable, Sendable {
    /// The rules for the model.
    var system: String
    var messages: [LLMMessage]
    /// The answer must be a single JSON object. Providers with a JSON mode can turn it on.
    var expectsJSON: Bool
    var maxOutputTokens: Int
}

struct LLMMessage: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: String
}

struct LLMResponse: Equatable, Sendable {
    var text: String
}

enum LLMProviderError: Error, Equatable, Sendable {
    /// No model is configured.
    case unavailable
    /// The model was reached but could not answer (network, quota, refusal).
    case failed(String)
}

/// What the runtime uses while no model is connected: it says so, it never invents a plan.
struct UnavailableLLMProvider: LLMProvider {
    var name: String { "none" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw LLMProviderError.unavailable
    }
}
