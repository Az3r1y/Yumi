import Foundation
import Testing

// Apple Intelligence's model as an engine: it plans on the Mac, and its plans are checked like
// any other engine's.

@Suite struct AppleEngineTests {
    @Test func aLongConversationKeepsItsLastMessage() {
        let messages = (0..<40).map { LLMMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: String(repeating: "x", count: 400) + "\($0)") }
        let prompt = AppleLLMProvider.prompt(messages)
        #expect(prompt.count <= 6_500)
        #expect(prompt.hasSuffix("39"))
        #expect(AppleLLMProvider.prompt([LLMMessage(role: .user, content: "Bonjour")]) == "Bonjour")
    }

    @Test func aFencedJSONAnswerIsUnwrapped() {
        #expect(AppleLLMProvider.unfenced("```json\n{\"a\": 1}\n```") == "{\"a\": 1}")
        #expect(AppleLLMProvider.unfenced("{\"a\": 1}") == "{\"a\": 1}")
    }

    @Test(.enabled(if: AppleLLMProvider.isAvailable, "Apple Intelligence is not on this Mac"))
    @MainActor func itPlansAReminderOnTheMac() async throws {
        var tools = ToolRegistry.standard
        // The tools of the app: the planner's rules name get_today
        try tools.register(AddReminderTool(store: EventKitReminderStore()))
        try tools.register(GetTodayTool(source: FixedToday(value: TodayFacts())))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: AppleLLMProvider()), tools: tools,
                                 policy: AgentPolicy(maximumRisk: .write))
        let planned = await agent.plan(for: AgentRequest(userIntent: "Rappelle-moi d'appeler le dentiste demain à 10h"))
        let plan = try planned.get()
        let step = try #require(plan.steps.first { $0.toolID == "add_reminder" })
        #expect(step.arguments["time"] == .string("10:00"))
    }
}
