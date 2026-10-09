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
    @MainActor func itCarriesOutAReminderOnTheMac() async throws {
        let store = FakeReminderStore()
        var tools = ToolRegistry.standard
        // The tools of the app: the planner's rules name get_today
        try tools.register(AddReminderTool(store: store))
        try tools.register(GetTodayTool(source: FixedToday(value: TodayFacts())))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: AppleLLMProvider()), tools: tools,
                                 permissions: ScriptedPermissionManager([.decision(.granted), .decision(.granted)]),
                                 policy: AgentPolicy(maximumRisk: .write), recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
        let result = await agent.run(AgentRequest(userIntent: "Rappelle-moi d'appeler le dentiste demain à 10h"))
        #expect(result.status == .completed, "\(result.status) \(String(describing: result.error))")
        #expect(store.all.first?.title.localizedCaseInsensitiveContains("dentiste") == true)
    }
}
