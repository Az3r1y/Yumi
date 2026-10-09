import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence's on-device model (macOS 26) as an engine: it plans and chats on the Mac,
/// without internet, without an account and without a bill. A small model with a short memory
/// (about 4,000 tokens): what it proposes goes through `PlanValidator`, the permissions and the
/// verification like any other engine's.
struct AppleLLMProvider: LLMProvider {
    var name: String { "apple-intelligence" }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), Self.isAvailable else { throw LLMProviderError.unavailable }
        var instructions = request.system
        if request.expectsJSON { instructions += "\n\nAnswer with one JSON object only, without Markdown fences." }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let answer = try await session.respond(to: Self.prompt(request.messages),
                                                   options: GenerationOptions(maximumResponseTokens: request.maxOutputTokens))
            return LLMResponse(text: Self.unfenced(answer.content))
        } catch {
            throw LLMProviderError.failed(error.localizedDescription)
        }
        #else
        throw LLMProviderError.unavailable
        #endif
    }

    /// The conversation as one prompt: the model answers the last message. Its memory is short:
    /// the oldest messages go first, the last one always stays.
    static func prompt(_ messages: [LLMMessage], budget: Int = 6_000) -> String {
        guard messages.count > 1 else { return messages.last?.content ?? "" }
        var kept: [String] = []
        var used = 0
        for message in messages.reversed() {
            let line = "\(message.role == .user ? "User" : "Assistant"): \(message.content)"
            if !kept.isEmpty, used + line.count > budget { break }
            kept.insert(line, at: 0)
            used += line.count
        }
        return kept.joined(separator: "\n\n")
    }

    /// A JSON answer sometimes comes wrapped in a Markdown block: the object alone.
    static func unfenced(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), let start = trimmed.firstIndex(of: "\n"), trimmed.hasSuffix("```") else { return trimmed }
        return String(trimmed[trimmed.index(after: start)..<trimmed.index(trimmed.endIndex, offsetBy: -3)])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
