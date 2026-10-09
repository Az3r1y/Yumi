import Foundation
import Testing

// Running a shortcut, opening an app, a page or a project.

private func toolContext() -> ToolContext { ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: Date()) }

@MainActor
private func runtime(_ json: String, tool: any Tool, permissions: any PermissionManager) throws -> RuntimeAgent {
    var tools = ToolRegistry.standard
    try tools.register(tool)
    return RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: json)), tools: tools, permissions: permissions,
                        policy: AgentPolicy(maximumRisk: .write), recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
}

private func step(_ tool: String, _ arguments: String) -> String {
    #"{"goal": "Test", "steps": [{"description": "Étape", "tool": "\#(tool)", "arguments": \#(arguments)}]}"#
}

/// The risk the real permission system gives a call.
private func assessed(_ tool: any Tool, _ arguments: ToolArguments) throws -> ActionAssessment {
    let request = AgentPermissionRequest(runID: UUID(), stepID: "step-1", goal: "g", reason: "r", toolID: tool.descriptor.id,
                                         toolName: tool.descriptor.name, risk: tool.descriptor.risk, arguments: arguments,
                                         action: tool.action(for: arguments), requiresApproval: true)
    return try RiskAssessor(home: "/Users/someone").assess(request).get()
}

// MARK: - Shortcuts

final class FakeShortcuts: ShortcutsLibrary, @unchecked Sendable {
    private let lock = NSLock()
    let list: [String]?
    var failure: Error?
    private var runs: [String] = []

    init(_ list: [String]?) { self.list = list }

    var ran: [String] { lock.withLock { runs } }
    func names() async -> [String]? { list }
    func run(_ name: String) async throws {
        if let failure { throw failure }
        lock.withLock { runs.append(name) }
    }
}

@MainActor
@Suite struct RunShortcutToolTests {
    @Test func aShortcutNamedLooselyRunsAfterTheApproval() async throws {
        let library = FakeShortcuts(["Mode travail", "Café"])
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let agent = try runtime(step("run_shortcut", #"{"name": "mode Travail "}"#), tool: RunShortcutTool(library: library),
                                permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Lance mon raccourci mode travail"))
        #expect(result.status == .completed)
        #expect(library.ran == ["Mode travail"])
        #expect(permissions.requests.count == 1)
        #expect(AgentLook.remark(for: result)?.text == "C'est fait, j'ai lancé « Mode travail ».")
    }

    @Test func itIsAlwaysAskedAndNeverRemembered() throws {
        let assessment = try assessed(RunShortcutTool(library: FakeShortcuts([])), ["name": .string("Supprimer tout")])
        #expect(assessment.risk >= .high)
        #expect(!assessment.isScoped)
    }

    @Test func anUnknownShortcutIsRefusedBeforeAsking() async throws {
        let library = FakeShortcuts(["Mode travail", "Café"])
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let agent = try runtime(step("run_shortcut", #"{"name": "Mode sieste"}"#), tool: RunShortcutTool(library: library),
                                permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Lance Mode sieste"))
        #expect(result.status != .completed)
        #expect(permissions.requests.isEmpty)
        #expect(library.ran.isEmpty)
        #expect(AgentLook.remark(for: result)?.text.contains("« Mode travail », « Café »") == true)
    }

    @Test func unreadableShortcutsOrAFailureAreSaid() async {
        #expect(await RunShortcutTool(library: FakeShortcuts(nil)).check(["name": .string("x")]) == "je n'arrive pas à lire tes raccourcis")
        let failing = FakeShortcuts(["Café"])
        failing.failure = ToolError.failed("plus de lait")
        await #expect(throws: ToolError.self) {
            try await RunShortcutTool(library: failing).execute(["name": .string("café")], in: toolContext())
        }
    }
}

// MARK: - Opening

final class FakeOpener: Opener, @unchecked Sendable {
    private let lock = NSLock()
    let apps: [String: URL]
    private var calls: [(URL?, URL?)] = []

    init(apps: [String] = ["Xcode", "Safari"]) {
        self.apps = Dictionary(uniqueKeysWithValues: apps.map { ($0.lowercased(), URL(fileURLWithPath: "/Applications/\($0).app")) })
    }

    var opened: [(URL?, URL?)] { lock.withLock { calls } }
    func application(named name: String) -> URL? { apps[name.lowercased()] }
    func open(_ target: URL?, with app: URL?) async throws { lock.withLock { calls.append((target, app)) } }
    func isRunning(_ app: URL) -> Bool { lock.withLock { calls.contains { $0.1 == app } } }
}

/// A home with a project in ~/Work, a script and an app bundle.
private func home() throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-\(UUID().uuidString)").path
    for folder in ["Work/Yumi/.git", "Work/Clients/Atlas", "Downloads/Outil.app"] {
        try FileManager.default.createDirectory(atPath: root + "/" + folder, withIntermediateDirectories: true)
    }
    FileManager.default.createFile(atPath: root + "/Downloads/installer.command", contents: Data("echo".utf8))
    FileManager.default.createFile(atPath: root + "/Downloads/notes.md", contents: Data("# Notes".utf8))
    return root
}

@MainActor
@Suite struct OpenToolTests {
    @Test func yumiInXcodeFindsTheProjectAndOpensItAfterApproval() async throws {
        let home = try home()
        let opener = FakeOpener()
        let permissions = ScriptedPermissionManager([.decision(.granted)])
        let agent = try runtime(step("open_item", #"{"target": "yumi", "app": "xcode"}"#), tool: OpenTool(opener: opener, home: home),
                                permissions: permissions)
        let result = await agent.run(AgentRequest(userIntent: "Ouvre Yumi dans Xcode"))
        #expect(result.status == .completed)
        let call = try #require(opener.opened.first)
        #expect(call.0?.path == home + "/Work/Yumi")
        #expect(call.1?.lastPathComponent == "Xcode.app")
        #expect(AgentLook.remark(for: result)?.text == "J'ai ouvert ~/Work/Yumi dans Xcode.")
        let asked = try #require(permissions.requests.first)
        #expect(asked.action?.kind == .run)
    }

    @Test func aProjectTwoLevelsDownIsFoundToo() throws {
        let home = try home()
        let plan = try OpenTool(opener: FakeOpener(), home: home).plan(["target": .string("Atlas")])
        #expect(plan.target == .item(home + "/Work/Clients/Atlas"))
    }

    @Test func anAppAloneIsLaunchedAndChecked() async throws {
        let opener = FakeOpener()
        let tool = OpenTool(opener: opener, home: try home())
        let output = try await tool.execute(["app": .string("safari")], in: toolContext())
        #expect(opener.opened.first?.0 == nil)
        #expect(await tool.verify(["app": .string("safari")], output: output) == nil)
    }

    @Test func aPageIsAskedEveryTimeWithItsWholeAddress() throws {
        let tool = OpenTool(opener: FakeOpener(), home: try home())
        let arguments: ToolArguments = ["target": .string("https://example.com/compte?id=42")]
        #expect(tool.action(for: arguments)?.content == "https://example.com/compte?id=42")
        #expect(try assessed(tool, arguments).risk >= .high)
    }

    @Test func nothingThatWouldRunAProgramIsOpened() async throws {
        let home = try home()
        let tool = OpenTool(opener: FakeOpener(), home: home)
        for target in ["~/Downloads/Outil.app", "~/Downloads/installer.command", "file:///etc/hosts",
                       "javascript:alert(1)", "ssh://serveur", "~/Downloads/absent.md", "Inconnu"] {
            #expect(await tool.check(["target": .string(target)]) != nil, "\(target)")
        }
        #expect(await tool.check(["target": .string("~/Downloads/notes.md")]) == nil)
        #expect(await tool.check(["app": .string("Photoshop")]) == "je ne trouve pas d'app « Photoshop » sur ce Mac")
        #expect(await tool.check([:]) != nil)
    }
}

@Suite struct OpenAndShortcutEnglishTests {
    @Test func theirSentencesReadInEnglish() throws {
        let tool = OpenTool(opener: FakeOpener(), home: "/Users/someone")
        AppLanguage.$forced.withValue("en") {
            #expect(tool.descriptor.name == "Open an app, a page or a project")
            #expect(loc("J'ai ouvert \(loc("\("~/Work/Yumi") dans \("Xcode")")).") == "I opened ~/Work/Yumi in Xcode.")
            #expect(loc("je ne trouve pas de raccourci « \("Sieste") ». Tu as : \("« Café »")") == "I can't find a shortcut “Sieste”. You have: « Café »")
        }
    }
}
