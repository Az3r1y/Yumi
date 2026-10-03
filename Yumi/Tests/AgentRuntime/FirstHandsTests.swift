import Foundation
import Testing

/// A folder that stands for the person's home, with a Desktop and Documents, removed after.
private final class TemporaryHome {
    let path: String

    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-home-\(UUID().uuidString)").path
        for folder in ["Desktop", "Documents", "Library"] {
            try FileManager.default.createDirectory(atPath: path + "/" + folder, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    func contents(_ relative: String) -> String? {
        FileManager.default.contents(atPath: path + "/" + relative).flatMap { String(data: $0, encoding: .utf8) }
    }
}

private let todo = "# Todo\n\n- [ ] Écrire le README\n- [ ] Lancer les tests\n- [ ] Préparer la release\n"

private func createArguments(_ path: String, _ content: String = todo) -> ToolArguments {
    ["path": .string(path), "content": .string(content)]
}

private func context() -> ToolContext {
    ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: Date())
}

@Suite struct CreateFileToolTests {
    @Test func createsTheFileOnTheDesktopAndChecksIt() async throws {
        let home = try TemporaryHome()
        let tool = CreateFileTool(home: home.path)
        let output = try await tool.execute(createArguments("~/Desktop/todo.md"), in: context())
        #expect(home.contents("Desktop/todo.md") == todo)
        #expect(output.summary == "Created ~/Desktop/todo.md.")
        #expect(output.values["bytes"] == .number(Double(Data(todo.utf8).count)))
        #expect(await tool.verify(createArguments("~/Desktop/todo.md"), output: output) == nil)
    }

    @Test func neverReplacesAFile() async throws {
        let home = try TemporaryHome()
        try "à garder".write(toFile: home.path + "/Desktop/todo.md", atomically: true, encoding: .utf8)
        let tool = CreateFileTool(home: home.path)
        await #expect(throws: ToolError.self) { try await tool.execute(createArguments("~/Desktop/todo.md"), in: context()) }
        #expect(home.contents("Desktop/todo.md") == "à garder")
    }

    @Test func refusesEverywhereElse() async throws {
        let home = try TemporaryHome()
        let tool = CreateFileTool(home: home.path)
        for path in ["~/Library/evil.md", "~/todo.md", "~/Desktop/../Library/evil.md", "/tmp/todo.md", "todo.md",
                     "~/Desktop/.hidden", "~/Desktop/missing/todo.md"] {
            await #expect(throws: ToolError.self, "\(path)") { try await tool.execute(createArguments(path), in: context()) }
        }
        #expect(home.contents("Library/evil.md") == nil)
    }

    @Test func refusesASymbolicLinkOutOfTheDesktop() async throws {
        let home = try TemporaryHome()
        try FileManager.default.createSymbolicLink(atPath: home.path + "/Desktop/out", withDestinationPath: home.path + "/Library")
        let tool = CreateFileTool(home: home.path)
        await #expect(throws: ToolError.self) { try await tool.execute(createArguments("~/Desktop/out/evil.md"), in: context()) }
        #expect(home.contents("Library/evil.md") == nil)
    }

    @Test func refusesTooMuchContent() async throws {
        let home = try TemporaryHome()
        let tool = CreateFileTool(home: home.path)
        let big = String(repeating: "a", count: CreateFileTool.maxBytes + 1)
        await #expect(throws: ToolError.self) { try await tool.execute(createArguments("~/Desktop/big.txt", big), in: context()) }
    }

    @Test func describesItsActionFromTheArgumentsOnly() {
        let tool = CreateFileTool(home: "/Users/someone")
        let action = tool.action(for: createArguments("~/Desktop/todo.md"))
        #expect(action == ToolAction(kind: .create, resources: [.file("/Users/someone/Desktop/todo.md")], reversible: true))
        #expect(tool.descriptor.risk == .write)
    }

    @Test func verificationNoticesAChangedFile() async throws {
        let home = try TemporaryHome()
        let tool = CreateFileTool(home: home.path)
        let output = try await tool.execute(createArguments("~/Desktop/todo.md"), in: context())
        try "autre chose".write(toFile: home.path + "/Desktop/todo.md", atomically: true, encoding: .utf8)
        #expect(await tool.verify(createArguments("~/Desktop/todo.md"), output: output) != nil)
        try FileManager.default.removeItem(atPath: home.path + "/Desktop/todo.md")
        #expect(await tool.verify(createArguments("~/Desktop/todo.md"), output: output) != nil)
    }
}

@Suite struct CreateFilePermissionTests {
    private let tool = CreateFileTool(home: Fixture.home)

    private func request(_ path: String) -> AgentPermissionRequest {
        let arguments = createArguments(path)
        return AgentPermissionRequest(runID: UUID(), stepID: "step-1", goal: "Créer une liste", reason: "Créer todo.md",
                                      toolID: tool.descriptor.id, toolName: tool.descriptor.name, risk: tool.descriptor.risk,
                                      arguments: arguments, action: tool.action(for: arguments), requiresApproval: true)
    }

    @Test func creatingOnTheDesktopIsAMediumRiskThatAsks() async throws {
        let presenter = await FakePresenter()
        let manager = await Fixture.manager(presenter: presenter)
        let evaluation = await manager.evaluate(request("~/Desktop/todo.md"), upcoming: [])
        guard case .ask(let approval) = evaluation else { Issue.record("expected ask, got \(evaluation)"); return }
        #expect(approval.riskLevel == .medium)
        #expect(approval.action == .create)
    }

    @Test func aSecretPathIsNeverAllowed() async throws {
        let presenter = await FakePresenter()
        let manager = await Fixture.manager(presenter: presenter)
        let evaluation = await manager.evaluate(request("~/.ssh/authorized_keys"), upcoming: [])
        guard case .deny = evaluation else { Issue.record("expected deny, got \(evaluation)"); return }
        #expect(await presenter.shown.isEmpty)
    }
}

@MainActor
@Suite struct FirstVerticalSliceTests {
    private func plan(_ path: String) -> String {
        let content = todo.replacingOccurrences(of: "\n", with: "\\n")
        return #"{"goal": "Créer todo.md sur le Bureau", "steps": [{"description": "Créer le fichier todo.md avec trois tâches", "tool": "create_file", "arguments": {"path": "\#(path)", "content": "\#(content)"}}]}"#
    }

    private func makeAgent(_ home: TemporaryHome, plan: String,
                           permissions: any PermissionManager) throws -> (RuntimeAgent, ScriptedLLMProvider) {
        let provider = ScriptedLLMProvider(json: plan)
        var tools = ToolRegistry.standard
        try tools.register(CreateFileTool(home: home.path))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: provider), tools: tools, permissions: permissions,
                                 policy: AgentPolicy(maximumRisk: .write), recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
        return (agent, provider)
    }

    @Test func aRequestBecomesAVerifiedFileAfterApproval() async throws {
        let home = try TemporaryHome()
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let (agent, provider) = try makeAgent(home, plan: plan("~/Desktop/todo.md"), permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Yumi, crée-moi un todo.md sur mon Bureau avec trois tâches."))

        #expect(result.status == .completed)
        #expect(home.contents("Desktop/todo.md") == todo)
        #expect(permissions.requests.map(\.toolID) == ["create_file"])
        #expect(permissions.requests.first?.action?.kind == .create)
        #expect(provider.requests.first?.messages.first?.content.contains("create_file") == true)
        let names = agent.current?.events.map(\.name) ?? []
        #expect(names == ["agentStarted", "planCreated", "approvalRequired", "approvalGranted", "stepStarted",
                          "stepCompleted", "verificationStarted", "agentCompleted"])
        #expect(AgentLook.remark(for: result)?.mood == .happy)
    }

    @Test func nothingIsWrittenWhenThePersonSaysNo() async throws {
        let home = try TemporaryHome()
        let permissions = ScriptedPermissionManager([.decision(.denied(reason: nil))])
        let (agent, _) = try makeAgent(home, plan: plan("~/Desktop/todo.md"), permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Crée todo.md"))
        #expect(result.status == .cancelled)
        #expect(home.contents("Desktop/todo.md") == nil)
        #expect(AgentLook.remark(for: result)?.text == "D'accord, je n'y touche pas.")
    }

    @Test func withoutTheWritePolicyThePlanIsRefused() async throws {
        let home = try TemporaryHome()
        let provider = ScriptedLLMProvider(json: plan("~/Desktop/todo.md"))
        var tools = ToolRegistry.standard
        try tools.register(CreateFileTool(home: home.path))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: provider), tools: tools,
                                 permissions: ScriptedPermissionManager([.decision(.granted)]))
        let result = await agent.run(AgentRequest(userIntent: "Crée todo.md"))
        #expect(result.status == .failed)
        #expect(home.contents("Desktop/todo.md") == nil)
    }

    @Test func aModelCannotWriteOutsideTheAllowedFolders() async throws {
        let home = try TemporaryHome()
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let (agent, _) = try makeAgent(home, plan: plan("~/Library/LaunchAgents.plist"), permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Crée todo.md"))
        #expect(result.status == .failed)
        #expect(home.contents("Library/LaunchAgents.plist") == nil)
    }

    @Test func aStepWhoseEffectIsMissingFailsTheRun() async throws {
        let liar = FakeTool(id: "pretend_write", risk: .none)
        liar.effectProblem = "the file is not there"
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: planJSON(tools: ["pretend_write"]))),
                                 tools: try ToolRegistry([liar]))
        let result = await agent.run(AgentRequest(userIntent: "Écris"))
        #expect(result.status == .failed)
        #expect(result.error == .verificationFailed("step-1: the file is not there"))
    }

    @Test func aSkippedOptionalStepMakesItPartial() async throws {
        let failing = FakeTool(id: "flaky", fallback: .error(ToolError.failed("broken")))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: planJSON([("safe", false), ("flaky", true)]))),
                                 tools: try ToolRegistry([FakeTool(id: "safe"), failing]), recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
        let result = await agent.run(AgentRequest(userIntent: "Fais"))
        #expect(result.status == .partial)
        #expect(result.status.succeeded)
        #expect(agent.state == .completed)
    }
}

@Suite struct AnthropicProviderTests {
    private let request = LLMRequest(system: "rules", messages: [LLMMessage(role: .user, content: "plan this")],
                                     expectsJSON: true, maxOutputTokens: 500)

    @Test func withoutAKeyItIsUnavailableAndSendsNothing() async {
        let sent = SentRequests()
        let provider = AnthropicLLMProvider(model: "m", apiKey: { "  " }, transport: { request in
            sent.add(request)
            return (Data(), HTTPURLResponse())
        })
        await #expect(throws: LLMProviderError.unavailable) { try await provider.complete(request) }
        #expect(sent.all.isEmpty)
    }

    @Test func sendsOnlyTheRequestAndReadsTheText() async throws {
        let sent = SentRequests()
        let provider = AnthropicLLMProvider(model: "test-model", apiKey: { "sk-test" }, transport: { request in
            sent.add(request)
            let body = #"{"content": [{"type": "text", "text": "{\"goal\": \"x\"}"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let response = try await provider.complete(request)
        #expect(response.text == #"{"goal": "x"}"#)
        let urlRequest = try #require(sent.all.first)
        #expect(urlRequest.url == AnthropicLLMProvider.endpoint)
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        let body = try #require(urlRequest.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(Set(body.keys) == ["model", "max_tokens", "system", "messages"])
        #expect(body["system"] as? String == "rules")
        #expect(provider.name == "anthropic:test-model")
    }

    @Test func anErrorNeverCarriesTheBodyOrTheKey() async {
        let provider = AnthropicLLMProvider(model: "m", apiKey: { "sk-secret" }, transport: { request in
            let body = #"{"error": {"type": "authentication_error", "message": "bad key sk-secret plan this"}}"#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await provider.complete(request)
            Issue.record("expected an error")
        } catch {
            #expect(error as? LLMProviderError == .failed("HTTP 401 authentication_error"))
            #expect(!String(describing: error).contains("sk-secret"))
        }
    }
}

private final class SentRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func add(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

@Suite struct AgentLookTests {
    @Test func everyActivityHasALook() {
        #expect(AgentLook.of(.planning).mood == .thinking)
        #expect(AgentLook.of(.working).mood == .focused)
        #expect(AgentLook.of(.checking).mood == .curious)
        #expect(AgentLook.of(.success).pose == .celebrate)
        #expect(AgentLook.of(.error).mood == .worried)
        #expect(AgentLook.of(.idle).pose == nil)
    }

    @Test func aCancelledRunSaysNothing() {
        let result = AgentResult(runID: UUID(), status: .cancelled, goal: nil, steps: [], error: .cancelled, finishedAt: Date())
        #expect(AgentLook.remark(for: result) == nil)
    }
}
