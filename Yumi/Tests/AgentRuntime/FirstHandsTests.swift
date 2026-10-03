import Foundation
import Testing

/// A folder that stands for the person's home, with a Desktop and Documents, removed after.
private final class TemporaryHome {
    let path: String

    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-home-\(UUID().uuidString)").path
        for folder in ["Downloads", "Desktop", "Documents", "Library"] {
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
        for path in ["~/Library/evil.md", "~/todo.md", "~/Desktop/../Library/evil.md", "/tmp/todo.md", "notes/todo.md",
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
        #expect(action == ToolAction(kind: .create, resources: [.file("/Users/someone/Desktop/todo.md")], reversible: true, content: todo))
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

    /// The person reads what the file will hold before agreeing, not only where it goes.
    @Test func theApprovalShowsWhatTheFileWillHold() async throws {
        let presenter = await FakePresenter()
        let manager = await Fixture.manager(presenter: presenter)
        let long = (1...8).map { "- [ ] Tâche \($0)" }.joined(separator: "\n") + "\n"
        let arguments = createArguments("~/Desktop/todo.md", long)
        let asked = AgentPermissionRequest(runID: UUID(), stepID: "step-1", goal: "Créer une liste", reason: "Créer todo.md",
                                           toolID: tool.descriptor.id, toolName: tool.descriptor.name, risk: tool.descriptor.risk,
                                           arguments: arguments, action: tool.action(for: arguments), requiresApproval: true)
        let approval = try #require(await manager.evaluate(asked, upcoming: []).approval)
        #expect(approval.contentPreview == ["- [ ] Tâche 1", "- [ ] Tâche 2", "- [ ] Tâche 3", "- [ ] Tâche 4", "- [ ] Tâche 5",
                                            "… et 3 lignes de plus"])
        #expect(approval.subject == nil)
        #expect(approval.details.contains("Contenu : 8 lignes, \(long.count) caractères"))

        let one = createArguments("~/Desktop/note.txt", "Bonjour\n")
        let short = AgentPermissionRequest(runID: UUID(), stepID: "step-1", goal: "g", reason: "r", toolID: tool.descriptor.id,
                                           toolName: tool.descriptor.name, risk: tool.descriptor.risk, arguments: one,
                                           action: tool.action(for: one), requiresApproval: true)
        let single = try #require(await manager.evaluate(short, upcoming: []).approval)
        #expect(single.subject == "« Bonjour »")
        #expect(single.contentPreview == nil)
    }

    /// Two files of the same run are asked one by one: each content is read on its own.
    @Test func twoFilesAreNeverAskedTogether() async throws {
        let presenter = await FakePresenter()
        let manager = await Fixture.manager(presenter: presenter)
        let run = UUID()
        func step(_ id: String, _ path: String) -> AgentPermissionRequest {
            let arguments = createArguments(path)
            return AgentPermissionRequest(runID: run, stepID: id, goal: "g", reason: "r", toolID: tool.descriptor.id,
                                          toolName: tool.descriptor.name, risk: tool.descriptor.risk, arguments: arguments,
                                          action: tool.action(for: arguments), requiresApproval: true)
        }
        let approval = try #require(await manager.evaluate(step("step-1", "~/Desktop/a.md"), upcoming: [step("step-2", "~/Desktop/b.md")]).approval)
        #expect(approval.items.count == 1)
        #expect(approval.content == todo)
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

    @Test func aRefusalIsNeverSaidAsASuccess() {
        let ruled = AgentResult(runID: UUID(), status: .failed, goal: nil, steps: [],
                                error: .permissionDenied(tool: "create_file", reason: "Une règle de tes réglages l'interdit."), finishedAt: Date())
        #expect(AgentLook.remark(for: ruled)?.text == "Une règle de tes réglages l'interdit. Je n'ai rien fait.")
        #expect(AgentLook.remark(for: ruled)?.mood == .worried)

        var refused = AgentStep(id: "step-2", description: "Ajouter", toolID: "append_to_file", isOptional: true)
        refused.status = .skipped
        refused.error = .permissionDenied(tool: "append_to_file", reason: "Tu as refusé.")
        var done = AgentStep(id: "step-1", description: "Créer", toolID: "create_file")
        done.status = .completed
        done.output = ToolOutput(summary: "Created.")
        let partial = AgentResult(runID: UUID(), status: .partial, goal: "todo", steps: [done, refused], error: nil, finishedAt: Date())
        #expect(AgentLook.remark(for: partial)?.text == "C'est fait en partie (todo) : tu as refusé une étape, je l'ai laissée.")
        #expect(AgentLook.remark(for: partial)?.mood != .happy)
    }

    @Test func aTimeoutSaysTheEffectMayBeThere() {
        let result = AgentResult(runID: UUID(), status: .failed, goal: nil, steps: [], error: .toolTimedOut(tool: "add_reminder"), finishedAt: Date())
        #expect(AgentLook.remark(for: result)?.text.contains("Je ne sais pas si c'est fait") == true)
    }
}

@MainActor
@Suite struct ChatRouteTests {
    private func agent(_ answer: String) throws -> RuntimeAgent {
        var tools = ToolRegistry.standard
        try tools.register(CreateFileTool(home: "/Users/someone"))
        return RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: answer)), tools: tools,
                            policy: AgentPolicy(maximumRisk: .write))
    }

    @Test func anActionOnTheMacGoesToTheRuntime() async throws {
        let json = #"{"goal": "Créer todo.md", "steps": [{"description": "Créer", "tool": "create_file", "arguments": {"path": "~/Desktop/todo.md", "content": "- a"}}]}"#
        let route = ChatRoute.route(await try agent(json).plan(for: AgentRequest(userIntent: "Crée todo.md sur mon Bureau")))
        guard case .agent(let plan) = route else { Issue.record("expected the runtime"); return }
        #expect(plan.requiredTools == ["create_file"])
    }

    @Test func talkingReadingAndFailuresStayInTheChat() async throws {
        let reading = planJSON(tools: ["get_current_time"])
        #expect(ChatRoute.route(await try agent(reading).plan(for: AgentRequest(userIntent: "Quelle heure est-il ?"))) == .chat)
        let talk = #"{"cannotPlan": "the person is talking"}"#
        #expect(ChatRoute.route(await try agent(talk).plan(for: AgentRequest(userIntent: "Salut Yumi"))) == .chat)
        let none = RuntimeAgent(planner: LLMAgentPlanner(provider: UnavailableLLMProvider()))
        #expect(ChatRoute.route(await none.plan(for: AgentRequest(userIntent: "Crée todo.md"))) == .chat)
    }

    @Test func thePlannerIsToldThatTalkIsForTheChat() {
        let prompt = PlannerPrompt.make(for: AgentRequest(userIntent: "Salut"), tools: ToolRegistry.standard.descriptors, maxSteps: 12)
        #expect(prompt.system.contains(#"{"cannotPlan": "reason", "isAction": false}"#))
        #expect(prompt.system.contains(#"{"cannotPlan": "reason", "isAction": true}"#))
    }
}

/// Documents (or any allowed folder) that Yumi cannot reach: said before asking, with the reason.
@MainActor
@Suite struct UnreachableFolderTests {
    private final class Home {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-locked-\(UUID().uuidString)").path
        init() throws {
            for folder in ["Downloads", "Desktop", "Documents"] {
                try FileManager.default.createDirectory(atPath: path + "/" + folder, withIntermediateDirectories: true)
            }
        }
        func lock(_ folder: String, _ mode: Int) throws {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path + "/" + folder)
        }
        deinit {
            for folder in ["Downloads", "Desktop", "Documents"] { try? lock(folder, 0o755) }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func plan(_ path: String) -> String {
        #"{"goal": "Créer notes-test.md", "steps": [{"description": "Créer", "tool": "create_file", "arguments": {"path": "\#(path)", "content": "- a"}}]}"#
    }

    private func agent(_ home: Home, _ path: String, _ permissions: ScriptedPermissionManager) throws -> RuntimeAgent {
        var tools = ToolRegistry.standard
        try tools.register(CreateFileTool(home: home.path))
        return RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: plan(path))), tools: tools,
                            permissions: permissions, policy: AgentPolicy(maximumRisk: .write),
                            recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
    }

    @Test func anUnreadableDocumentsFolderIsSaidBeforeAskingWithItsReason() async throws {
        let home = try Home()
        try home.lock("Documents", 0o000)
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let result = await try agent(home, "~/Documents/notes-test.md", permissions).run(AgentRequest(userIntent: "crée-moi notes-test.md dans Documents"))
        #expect(result.status == .failed)
        #expect(permissions.requests.isEmpty)
        guard case .cannotRun(let tool, let reason)? = result.error else { Issue.record("got \(String(describing: result.error))"); return }
        #expect(tool == "create_file")
        #expect(reason.contains("~/Documents"))
        let text = AgentLook.remark(for: result)?.text ?? ""
        #expect(text.contains(reason))
        #expect(text.contains("je ne t'ai rien demandé"))
    }

    @Test func aReadOnlyFolderIsSaidBeforeAsking() async throws {
        let home = try Home()
        try home.lock("Documents", 0o555)
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let result = await try agent(home, "~/Documents/notes-test.md", permissions).run(AgentRequest(userIntent: "crée notes-test.md dans Documents"))
        #expect(permissions.requests.isEmpty)
        #expect(result.error == .cannotRun(tool: "create_file", reason: "je n'ai pas le droit d'écrire dans ~/Documents"))
    }

    @Test func aRefusedPlaceAndAnExistingFileAreSaidBeforeAsking() async throws {
        let home = try Home()
        try "x".write(toFile: home.path + "/Documents/notes-test.md", atomically: true, encoding: .utf8)
        for (path, expected) in [("~/Library/notes.md", "pas dans ~/Library"),
                                 ("~/Documents/notes-test.md", "existe déjà")] {
            let permissions = ScriptedPermissionManager([.decision(.granted)])
            let result = await try agent(home, path, permissions).run(AgentRequest(userIntent: "crée"))
            #expect(permissions.requests.isEmpty, "\(path)")
            guard case .cannotRun(_, let reason)? = result.error else { Issue.record("\(path): \(String(describing: result.error))"); continue }
            #expect(reason.contains(expected), "\(reason)")
        }
    }

    @Test func aWriteThatFailsAfterApprovalSaysWhy() async throws {
        // Locked between the check and the write: the failure carries the system's reason.
        let home = try Home()
        let tool = CreateFileTool(home: home.path)
        let arguments: ToolArguments = ["path": .string("~/Documents/notes-test.md"), "content": .string("- a")]
        #expect(await tool.check(arguments) == nil)
        try home.lock("Documents", 0o555)
        do {
            _ = try await tool.execute(arguments, in: ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: Date()))
            Issue.record("expected a failure")
        } catch ToolError.failed(let reason) {
            #expect(reason == "je n'ai pas le droit d'écrire dans ~/Documents")
        }
        let failed = AgentResult(runID: UUID(), status: .failed, goal: nil, steps: [],
                                 error: .toolFailed(tool: "create_file", reason: "je n'ai pas le droit d'écrire dans ~/Documents", transient: false),
                                 finishedAt: Date())
        #expect(AgentLook.remark(for: failed)?.text == "Je n'ai pas pu : je n'ai pas le droit d'écrire dans ~/Documents.")
    }

    @Test func aReachableDocumentsFolderWorks() async throws {
        let home = try Home()
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let result = await try agent(home, "~/Documents/notes-test.md", permissions).run(AgentRequest(userIntent: "crée notes-test.md dans Documents"))
        #expect(result.status == .completed)
        #expect(permissions.requests.count == 1)
        #expect(FileManager.default.fileExists(atPath: home.path + "/Documents/notes-test.md"))
    }
}
