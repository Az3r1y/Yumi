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
        if request.expectsJSON {
            // A small model drifts: the rules it needs said twice, plainly
            instructions += """


                Answer with one JSON object only, without Markdown fences. In each step, use only the argument \
                names listed for that tool, never others, and leave out the optional ones you do not need. \
                Use as few steps as possible: one step is enough when one tool does what is asked. Work out \
                dates and times yourself from <now>, as YYYY-MM-DD and HH:mm: never add a step only to read the \
                date, the time or the day before acting.
                """
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            // A plan is the same for the same request: no sampling when JSON is expected
            let options = request.expectsJSON
                ? GenerationOptions(sampling: .greedy, maximumResponseTokens: request.maxOutputTokens)
                : GenerationOptions(maximumResponseTokens: request.maxOutputTokens)
            // A plan: the model is kept to the tools' ids and arguments by the framework itself
            if request.expectsJSON, let tools = request.tools, !tools.isEmpty {
                let guided = try await session.respond(to: Self.prompt(request.messages), schema: Self.planSchema(tools),
                                                       options: options)
                return LLMResponse(text: guided.content.jsonString)
            }
            let answer = try await session.respond(to: Self.prompt(request.messages), options: options)
            return LLMResponse(text: Self.unfenced(answer.content))
        } catch {
            throw LLMProviderError.failed(error.localizedDescription)
        }
        #else
        throw LLMProviderError.unavailable
        #endif
    }

    #if canImport(FoundationModels)
    /// A plan as `PlanProposal` reads it, or the reason no plan fits: each step one of the tools,
    /// with exactly its arguments, required ones required. The model cannot name anything else.
    @available(macOS 26.0, *)
    static func planSchema(_ tools: [ToolDescriptor]) throws -> GenerationSchema {
        let text = DynamicGenerationSchema(type: String.self)
        let steps = tools.map { tool in
            let arguments = tool.inputSchema.fields.map { field in
                DynamicGenerationSchema.Property(name: field.name, description: field.description, schema: {
                    switch field.type {
                    case .string: DynamicGenerationSchema(type: String.self)
                    case .number: DynamicGenerationSchema(type: Double.self)
                    case .bool: DynamicGenerationSchema(type: Bool.self)
                    }
                }(), isOptional: !field.required)
            }
            return DynamicGenerationSchema(name: "step_\(tool.id)", description: tool.description, properties: [
                .init(name: "description", description: "what this step does, in a few words", schema: text),
                .init(name: "tool", schema: DynamicGenerationSchema(name: "tool_\(tool.id)", anyOf: [tool.id])),
                .init(name: "arguments", schema: DynamicGenerationSchema(name: "arguments_\(tool.id)", properties: arguments)),
            ])
        }
        let plan = DynamicGenerationSchema(name: "Plan", properties: [
            .init(name: "goal", description: "what the plan achieves", schema: text),
            .init(name: "steps", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(name: "Step", anyOf: steps),
                                                                minimumElements: 1, maximumElements: 12)),
        ])
        let refusal = DynamicGenerationSchema(name: "CannotPlan", properties: [
            .init(name: "cannotPlan", description: "why the tools cannot do what is asked", schema: text),
            .init(name: "isAction", description: "true when the person asked to change something on the Mac",
                  schema: DynamicGenerationSchema(type: Bool.self)),
        ])
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Answer", anyOf: [plan, refusal]), dependencies: [])
    }
    #endif

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
