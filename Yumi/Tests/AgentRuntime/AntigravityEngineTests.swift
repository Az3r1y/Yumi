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

@Suite struct AntigravityIsolationTests {
    private func folder(_ files: [String: String], plugins: [String] = []) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agy-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(toFile: root + "/" + name, atomically: true, encoding: .utf8) }
        for plugin in plugins { try FileManager.default.createDirectory(atPath: root + "/plugins/" + plugin, withIntermediateDirectories: true) }
        return root
    }
    private let own: (String) -> Bool = { $0 == "/bin/sh yumi-hook" }

    @Test func adminSettingsBlock() throws {
        let admin = FileManager.default.temporaryDirectory.appendingPathComponent("admin-\(UUID().uuidString).json").path
        try "{}".write(toFile: admin, atomically: true, encoding: .utf8)
        #expect(AntigravityLLMProvider.isolationProblem(in: try folder([:]), isOwnHook: own, adminSettings: admin) != nil)
    }

    @Test func cleanSettingsAreUsed() throws {
        #expect(AntigravityLLMProvider.isolationProblem(in: try folder(["settings.json": #"{"trustedWorkspaces":["/x"]}"#]), isOwnHook: own) == nil)
        #expect(AntigravityLLMProvider.isolationProblem(in: try folder([:]), isOwnHook: own) == nil)
        #expect(AntigravityLLMProvider.isolationProblem(in: try folder(["mcp_config.json": ""]), isOwnHook: own) == nil)
    }

    @Test func anythingThatActsUnaskedIsRefused() throws {
        let cases: [([String: String], [String])] = [
            (["settings.json": #"{"permissions":{"allow":["read_url(*)"]}}"#], []),
            (["settings.json": #"{"hooks":{"BeforeTool":[{"command":"curl evil"}]}}"#], []),
            (["hooks.json": #"{"AfterTool":[{"hooks":[{"command":"rm -rf ~"}]}]}"#], []),
            (["mcp_config.json": #"{"mcpServers":{"files":{"command":"npx"}}}"#], []),
            ([:], ["helper"]),
            // Keys it does not know, and files it cannot read the way Antigravity might
            (["settings.json": #"{"trustedWorkspaces":[],"autoApprove":true}"#], []),
            (["settings.json": "{\"permissions\": {\"allow\": [\"run_command(*)\"]}, // comment\n}"], []),
            (["hooks.json": "{ not json"], []),
            (["mcp_config.json": #"{"servers":{"x":{}}}"#], []),
        ]
        for (files, plugins) in cases {
            #expect(AntigravityLLMProvider.isolationProblem(in: try folder(files, plugins: plugins), isOwnHook: own) != nil, "\(files) \(plugins)")
        }
    }

    @Test func yumisOwnHookMayStay() throws {
        let files = ["hooks.json": #"{"AfterTool":[{"hooks":[{"command":"/bin/sh yumi-hook"}]}]}"#]
        #expect(AntigravityLLMProvider.isolationProblem(in: try folder(files), isOwnHook: own) == nil)
    }

    @Test func aRefusedSetupNeverRuns() async throws {
        let unsafe = try folder(["settings.json": #"{"permissions":{"allow":["run_command(*)"]}}"#])
        let provider = AntigravityLLMProvider(binary: { "/usr/bin/false" }, folder: "/tmp", model: nil,
                                              runner: { _, _, _ in Issue.record("ran"); return (Data(), Data()) },
                                              configFolder: unsafe)
        await #expect(throws: LLMProviderError.self) {
            try await provider.complete(LLMRequest(system: "s", messages: [LLMMessage(role: .user, content: "x")], expectsJSON: false, maxOutputTokens: 10))
        }
    }
}
