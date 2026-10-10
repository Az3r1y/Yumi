import Foundation
import Testing

// Antigravity as an engine: read-only by its flags, kept to the tools by its schema.

@Suite struct AntigravityEngineTests {
    @Test func itAlwaysRunsReadOnly() {
        let arguments = AntigravityLLMProvider.arguments(prompt: "p", model: "gemini-3.8-flash-low", schema: nil)
        #expect(arguments.contains("--sandbox"))
        #expect(arguments.firstIndex(of: "--mode").map { arguments[$0 + 1] } == "plan")
        // It would turn plan mode off
        #expect(!arguments.contains("--disable-slash-commands"))
        #expect(!arguments.contains("--dangerously-skip-permissions"))
    }

    @Test func thePlanSchemaNamesOnlyTheTools() throws {
        let tools = [ToolDescriptor(id: "add_reminder", name: "R", description: "d",
                                    inputSchema: ToolInputSchema(fields: [.init(name: "title", type: .string, required: true, description: "t"),
                                                                          .init(name: "time", type: .string, required: false, description: "h")]),
                                    risk: .write, outputKeys: [])]
        let text = try #require(AntigravityLLMProvider.planSchema(tools))
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(text.contains("\"enum\":[\"add_reminder\"]"))
        #expect(text.contains("\"required\":[\"title\"]"))
        #expect(text.contains("\"additionalProperties\":false"))
    }

    @Test func anEmptyRefusalIsNotARefusal() throws {
        let answer = #"{"status":"ok","response":"…","structured_output":{"cannotPlan":"","isAction":true,"goal":"g","steps":[{"description":"d","tool":"add_reminder","arguments":{"title":"Pain"}}]}}"#
        let text = try AntigravityLLMProvider.read(Data(answer.utf8), errors: Data()).text
        let proposal = try JSONDecoder().decode(PlanProposal.self, from: Data(text.utf8))
        #expect(proposal.cannotPlan == nil)
        #expect(proposal.steps?.first?.tool == "add_reminder")
        #expect(try AntigravityLLMProvider.read(Data(#"{"response":"Bonjour"}"#.utf8), errors: Data()).text == "Bonjour")
    }

    @Test func notSignedInCountsAsMissing() {
        #expect(throws: LLMProviderError.unavailable) {
            try AntigravityLLMProvider.read(Data(), errors: Data("Error: Please sign in to continue".utf8))
        }
    }

    @Test func notInstalledIsUnavailable() async {
        let provider = AntigravityLLMProvider(binary: { nil }, folder: "/tmp", model: nil)
        await #expect(throws: LLMProviderError.unavailable) {
            try await provider.complete(LLMRequest(system: "s", messages: [], expectsJSON: false, maxOutputTokens: 10))
        }
    }
}
