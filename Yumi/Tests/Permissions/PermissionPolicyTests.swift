import Testing
import Foundation

/// The rules of the settings, the risk table and the audit log.
@MainActor
@Suite struct PermissionPolicyTests {
    private let presenter = FakePresenter()
    private let reader = ActionTool(id: "read_file", kind: .read, risk: .read)
    private let editor = ActionTool(id: "modify_file", kind: .modify)

    @Test func rulesDecideInOrderDenyAskAllow() async {
        let manager = Fixture.manager(presenter: presenter)
        #expect(manager.addRule(PolicyRule(toolID: "read_file", target: .project(Fixture.yumi), effect: .allow)))
        #expect(await manager.evaluate(Fixture.request(reader, Fixture.file("a.md")), upcoming: []) == .allow)
        #expect(await manager.evaluate(Fixture.request(reader, Fixture.file("a.md", in: Fixture.other)), upcoming: []).approval != nil)
        #expect(manager.audit.entries.first?.decidedBy == .rule)

        #expect(manager.addRule(PolicyRule(toolID: "modify_file", target: .project(Fixture.yumi), effect: .ask)))
        #expect(manager.addRule(PolicyRule(toolID: "modify_file", target: .project(Fixture.yumi), effect: .allow)))
        #expect(await manager.evaluate(Fixture.request(editor, Fixture.file("a.swift")), upcoming: []).approval != nil)

        #expect(manager.addRule(PolicyRule(toolID: "*", kind: .read, target: .project(Fixture.yumi + "/Private"), effect: .deny)))
        #expect(await manager.evaluate(Fixture.request(reader, Fixture.file("Private/diary.md")), upcoming: []).isDeny)
    }

    @Test func nothingCanBeAllowedEverywhere() {
        let manager = Fixture.manager()
        #expect(!manager.addRule(PolicyRule(toolID: "*", target: .project(Fixture.yumi), effect: .allow)))
        #expect(!manager.addRule(PolicyRule(toolID: "modify_file", target: .anywhere, effect: .allow)))
        #expect(!manager.addRule(PolicyRule(toolID: "modify_file", target: .project("/"), effect: .allow)))
        #expect(!manager.addRule(PolicyRule(toolID: "modify_file", target: .project("relative/path"), effect: .allow)))
        #expect(!manager.addRule(PolicyRule(toolID: "Not An Id", target: .anywhere, effect: .deny)))
        #expect(manager.addRule(PolicyRule(toolID: "*", kind: .delete, target: .anywhere, effect: .deny)))
        #expect(manager.policy.rules.count == 1)
    }

    @Test func rulesArePersisted() async {
        let store = MemoryPermissionStore()
        let manager = Fixture.manager(store: store, presenter: presenter)
        let rule = PolicyRule(toolID: "send_email", target: .account("gmail:me@example.com"), effect: .ask)
        #expect(manager.addRule(rule))
        #expect(Fixture.manager(store: store).policy.rules == [rule])
        manager.removeRule(rule.id)
        #expect(store.load().rules.isEmpty)
    }

    @Test func theRiskTableIsConfigurableAboveItsFloors() {
        var table = RiskTable.standard
        table.levels[.read] = .medium
        table.levels[.delete] = .safe
        table.levels[.send] = .low
        #expect(table.level(for: .read) == .medium)
        #expect(table.level(for: .delete) == .high)
        #expect(table.level(for: .send) == .high)
        #expect(table.level(for: .pay) == .critical)
    }

    @Test func aToolCannotDescribeAChangeAsHarmless() {
        let lying = AgentPermissionRequest(runID: UUID(), stepID: "s", goal: "g", reason: "r", toolID: "sender", toolName: "Sender",
                                           risk: .external, arguments: [:],
                                           action: ToolAction(kind: .send, resources: [ResourceRef(.account, "gmail:me")]),
                                           requiresApproval: true)
        guard case .success(let assessment) = Fixture.assessor.assess(lying) else { Issue.record("refused"); return }
        #expect(assessment.risk == .high)
    }

    // MARK: - Audit

    @Test func theAuditLogKeepsDecisionsAndNoSecret() async {
        let sink = MemoryAuditSink()
        let manager = Fixture.manager(audit: PermissionAuditLog(sink: sink), presenter: presenter)
        let fetcher = ActionTool(id: "fetch_page", kind: .read, risk: .read)
        let run = UUID()
        _ = await manager.evaluate(Fixture.request(fetcher, ["url": .string("https://api.example.com/v1?token=ghp_abcdefghijklmnopqrstuvwxyz0123")], run: run),
                                   upcoming: [])
        let token = "ghp_" + String(repeating: "a", count: 36)
        let edit = Fixture.request(editor, Fixture.file("App/\(token).swift"), run: run,
                                   reason: "password=hunter2 apikey: sk-1234567890abcdefghij")
        let approval = try? #require(await manager.evaluate(edit, upcoming: []).approval)
        presenter.answerLast(.approveOnce)
        _ = await manager.decision(on: approval!)

        let entries = sink.load()
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.runID == run)
        #expect(entry.toolID == "modify_file")
        #expect(entry.risk == .medium)
        #expect(entry.decision == .approved)
        #expect(entry.scope == .oneTime)
        #expect(entry.decidedBy == .user)
        let encoded = String(decoding: try! JSONEncoder().encode(entries), as: UTF8.self)
        #expect(!encoded.contains(token))
        #expect(!encoded.contains("hunter2"))
        #expect(!encoded.contains("sk-1234"))
        #expect(!encoded.contains("token="))
        // The pending read of the page is not in the history until it ends.
        #expect(manager.waitingApprovals.count == 1)
        #expect(manager.waitingApprovals[0].resources == [ResourceRef(.url, "https://api.example.com")])
    }

    @Test func theRedactorKeepsOrdinaryNames() {
        #expect(AuditRedactor.clean("App/AuthService.swift") == "App/AuthService.swift")
        #expect(AuditRedactor.clean("Sources/App/AgentRuntime/AgentExecutor.swift") == "Sources/App/AgentRuntime/AgentExecutor.swift")
        #expect(AuditRedactor.clean("Authorization: Bearer abc.def") == "•••")
        #expect(AuditRedactor.clean("https://me:pw@example.com/x?key=1") == "https•••example.com/x•••")
    }

    @Test func theAuditFileIsPrivateAndSurvivesARestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("permissions-audit.jsonl")
        let log = PermissionAuditLog(sink: FileAuditSink(url: url, limit: 10))
        for index in 0..<12 {
            log.record(PermissionAuditEntry(date: Date(), runID: nil, stepID: "step-\(index)", approvalID: nil, toolID: "read_file",
                                            action: "read", resources: ["a.md"], resourceCount: 1, risk: .low,
                                            decision: .allowed, scope: nil, decidedBy: .defaults))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let reread = PermissionAuditLog(sink: FileAuditSink(url: url, limit: 10))
        #expect(reread.entries.count <= 10)
        #expect(reread.entries.last?.stepID == "step-11")
        reread.clear()
        #expect(PermissionAuditLog(sink: FileAuditSink(url: url)).entries.isEmpty)
    }

    @Test func thePermissionFileIsPrivateAndReadBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yumi-perm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("permissions.json")
        let store = FilePermissionStore(url: url)
        let rule = PolicyRule(toolID: "read_file", target: .project(Fixture.yumi), effect: .allow)
        store.save(PermissionRecord(rules: [rule]))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(FilePermissionStore(url: url).load().rules == [rule])
    }
}
