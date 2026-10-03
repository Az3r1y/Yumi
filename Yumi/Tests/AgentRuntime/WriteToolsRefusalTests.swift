import Foundation
import Testing

// The four tools that write, with the real permission manager: whatever way the person does not
// say yes (a refusal, no answer, a cancelled run), nothing is written, created or saved. And a
// yes is good for one call only: the same request asks again.

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()
/// Saturday 3 October 2026, 9:00 in Paris.
private let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!

/// How the person does not say yes.
enum NoAnswer: CaseIterable, Sendable { case refused, expired, cancelled }

/// A home folder of its own, removed at the end. Not in the temporary folder: it lies under
/// `/private`, which the permission system refuses as a system place before asking anyone.
private final class TemporaryHome {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/app.yumi.tests/refusal-\(UUID().uuidString)").path
    init() throws {
        for folder in ["Downloads", "Desktop", "Documents"] {
            try FileManager.default.createDirectory(atPath: path + "/" + folder, withIntermediateDirectories: true)
        }
    }
    deinit { try? FileManager.default.removeItem(atPath: path) }
    func read(_ relative: String) -> String? { try? String(contentsOfFile: path + "/" + relative, encoding: .utf8) }
}

@MainActor
@Suite struct WriteToolsRefusalTests {
    private let presenter = FakePresenter()

    private func plan(_ tool: String, _ arguments: String) -> String {
        #"{"goal": "Test", "steps": [{"description": "Étape", "tool": "\#(tool)", "arguments": \#(arguments)}]}"#
    }

    /// Runs the plan and ends it without a yes, the way asked.
    private func run(_ json: String, tool: any Tool, _ way: NoAnswer) async throws -> AgentResult {
        let manager = Fixture.manager(lifetime: way == .expired ? .milliseconds(50) : .seconds(60), presenter: presenter)
        if way == .refused { presenter.autoAnswer = .deny }
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: json)), tools: try ToolRegistry([tool]),
                                 permissions: manager, policy: AgentPolicy(maximumRisk: .write),
                                 recovery: RecoveryPolicy(retryDelay: .zero), sleep: { _ in })
        let running = Task { await agent.run(AgentRequest(userIntent: "x")) }
        if way == .cancelled {
            #expect(await eventuallyTrue { agent.state == .awaitingApproval })
            agent.cancel()
        }
        let result = await running.value
        // An answer that comes after the end changes nothing.
        presenter.answerLast(.approveOnce)
        #expect(manager.waitingApprovals.isEmpty)
        return result
    }

    private func expectNothingRan(_ result: AgentResult, _ way: NoAnswer, tool: String) {
        #expect(!result.status.succeeded)
        #expect(result.status == .cancelled)
        switch way {
        case .refused: #expect(result.error == .permissionDenied(tool: tool, reason: "Tu as refusé."))
        case .expired: #expect(result.error == .approvalExpired(tool: tool))
        case .cancelled: #expect(result.error == .cancelled)
        }
        #expect(result.steps.allSatisfy { $0.status != .completed && $0.output == nil })
    }

    @Test(arguments: NoAnswer.allCases)
    func createFileWritesNothing(_ way: NoAnswer) async throws {
        let home = try TemporaryHome()
        let tool = CreateFileTool(home: home.path, log: MemoryCreatedFilesLog())
        let result = try await run(plan("create_file", #"{"path": "~/Desktop/todo.md", "content": "- a"}"#), tool: tool, way)
        expectNothingRan(result, way, tool: "create_file")
        #expect(home.read("Desktop/todo.md") == nil)
    }

    @Test(arguments: NoAnswer.allCases)
    func appendToFileAddsNothing(_ way: NoAnswer) async throws {
        let home = try TemporaryHome()
        let log = MemoryCreatedFilesLog()
        _ = try await CreateFileTool(home: home.path, log: log)
            .execute(["path": .string("~/Downloads/todo.md"), "content": .string("# Todo\n")],
                     in: ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: now))
        let tool = AppendToFileTool(log: log, home: home.path)
        let result = try await run(plan("append_to_file", #"{"path": "todo.md", "text": "- [ ] Pain"}"#), tool: tool, way)
        expectNothingRan(result, way, tool: "append_to_file")
        #expect(home.read("Downloads/todo.md") == "# Todo\n")
    }

    @Test(arguments: NoAnswer.allCases)
    func addReminderSavesNothing(_ way: NoAnswer) async throws {
        let store = FakeReminderStore()
        let tool = AddReminderTool(store: store, calendar: calendar, now: { now })
        let result = try await run(plan("add_reminder", #"{"title": "Appeler le dentiste", "date": "2026-10-04", "time": "10:00"}"#), tool: tool, way)
        expectNothingRan(result, way, tool: "add_reminder")
        #expect(store.all.isEmpty)
    }

    @Test(arguments: NoAnswer.allCases)
    func addEventSavesNothing(_ way: NoAnswer) async throws {
        let store = FakeEventStore()
        let tool = AddEventTool(store: store, calendar: calendar, now: { now })
        let result = try await run(plan("add_event", #"{"title": "Réunion client", "date": "2026-10-08", "time": "14:00"}"#), tool: tool, way)
        expectNothingRan(result, way, tool: "add_event")
        #expect(store.all.isEmpty)
    }

    /// The same request twice: the yes of the first is spent, the second asks again.
    @Test func aYesIsGoodForOneCallOnly() async throws {
        let store = FakeReminderStore()
        let tool = AddReminderTool(store: store, calendar: calendar, now: { now })
        let manager = Fixture.manager(presenter: presenter)
        presenter.autoAnswer = .approveOnce
        let json = plan("add_reminder", #"{"title": "Appeler le dentiste"}"#)
        for _ in 0..<2 {
            let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: json)), tools: try ToolRegistry([tool]),
                                     permissions: manager, policy: AgentPolicy(maximumRisk: .write), sleep: { _ in })
            #expect(await agent.run(AgentRequest(userIntent: "Rappelle-moi d'appeler le dentiste")).status == .completed)
        }
        #expect(presenter.shown.count == 2)
        #expect(store.all.count == 2)
        #expect(manager.sessionPermissions.isEmpty)
    }
}
