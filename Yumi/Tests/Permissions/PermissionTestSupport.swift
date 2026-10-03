import Foundation

// Test doubles for the permission system. None of them exists in the app.

/// Shows approvals to nobody: the test reads them and answers, or lets one answer itself.
@MainActor
final class FakePresenter: ApprovalPresenter {
    private(set) var shown: [ApprovalRequest] = []
    private(set) var withdrawn: [UUID] = []
    /// Kept after use, so a test can try to answer twice.
    private var answers: [UUID: @MainActor (ApprovalAnswer) -> Void] = [:]
    /// Answered as soon as shown, when set.
    var autoAnswer: ApprovalAnswer?
    /// False: approvals wait in a queue, as behind a Claude Code request in the island, until
    /// `bringOnScreen` is called. True (the default): on screen at once.
    var showsAtOnce = true
    private var onScreen: [UUID: @MainActor () -> Void] = [:]

    func present(_ approval: ApprovalRequest, shown: @escaping @MainActor () -> Void,
                 answer: @escaping @MainActor (ApprovalAnswer) -> Void) {
        self.shown.append(approval)
        answers[approval.id] = answer
        if showsAtOnce { shown() } else { onScreen[approval.id] = shown }
        if let autoAnswer { Task { @MainActor in answer(autoAnswer) } }
    }

    /// The approval reaches the front of the queue.
    func bringOnScreen(_ id: UUID) { onScreen.removeValue(forKey: id)?() }

    func withdraw(_ approvalID: UUID) { withdrawn.append(approvalID) }

    func answer(_ id: UUID, _ answer: ApprovalAnswer) { answers[id]?(answer) }

    func answerLast(_ answer: ApprovalAnswer) {
        guard let last = shown.last else { return }
        self.answer(last.id, answer)
    }
}

/// A tool that describes its action from its arguments: `path`, `paths` (comma separated),
/// `command` or `url`, with a fixed kind.
final class ActionTool: Tool, @unchecked Sendable {
    let descriptor: ToolDescriptor
    let kind: ActionKind
    let reversible: Bool
    private let lock = NSLock()
    private var count = 0

    init(id: String, kind: ActionKind, risk: ToolRisk = .write, reversible: Bool = true) {
        self.kind = kind
        self.reversible = reversible
        descriptor = ToolDescriptor(
            id: id, name: id, description: "A tool for the tests.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "path", type: .string, required: false, description: "a file"),
                .init(name: "paths", type: .string, required: false, description: "files"),
                .init(name: "command", type: .string, required: false, description: "a command"),
                .init(name: "url", type: .string, required: false, description: "a page"),
                .init(name: "account", type: .string, required: false, description: "an account"),
            ]),
            risk: risk, outputKeys: [])
    }

    var calls: Int { lock.withLock { count } }

    func action(for arguments: ToolArguments) -> ToolAction? {
        var resources: [ResourceRef] = []
        if case .string(let path)? = arguments["path"] { resources.append(.file(path)) }
        if case .string(let paths)? = arguments["paths"] {
            resources += paths.split(separator: ",").map { .file(String($0)) }
        }
        if case .string(let command)? = arguments["command"] { resources.append(ResourceRef(.command, command)) }
        if case .string(let url)? = arguments["url"] { resources.append(ResourceRef(.url, url)) }
        if case .string(let account)? = arguments["account"] { resources.append(ResourceRef(.account, account)) }
        return ToolAction(kind: kind, resources: resources, reversible: reversible)
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        lock.withLock { count += 1 }
        return ToolOutput(summary: "\(descriptor.id) done")
    }
}

enum Fixture {
    static let home = "/Users/someone"
    static let yumi = "/Users/someone/Yumi"
    static let other = "/Users/someone/other"
    static let yumiOld = "/Users/someone/Yumi-old"

    /// Two projects side by side, and a third whose name starts like the first.
    static let assessor = RiskAssessor(projectRoot: { path in
        for root in [yumi, other, yumiOld] where RiskAssessor.path(path, isInside: root) { return root }
        return nil
    }, home: home)

    @MainActor
    static func manager(store: any PermissionStore = MemoryPermissionStore(),
                        audit: PermissionAuditLog = PermissionAuditLog(sink: MemoryAuditSink()),
                        lifetime: Duration = .seconds(60),
                        queue: Duration = .seconds(600),
                        presenter: FakePresenter? = nil) -> LocalPermissionManager {
        let manager = LocalPermissionManager(store: store, audit: audit, assessor: assessor, approvalLifetime: lifetime,
                                             queueLifetime: queue)
        manager.presenter = presenter
        return manager
    }

    static func request(_ tool: ActionTool, _ arguments: ToolArguments, run: UUID = UUID(), step: String = "step-1",
                        reason: String = "Corriger l'erreur", goal: String = "Corriger le projet") -> AgentPermissionRequest {
        AgentPermissionRequest(runID: run, stepID: step, goal: goal, reason: reason, toolID: tool.descriptor.id,
                               toolName: tool.descriptor.name, risk: tool.descriptor.risk, arguments: arguments,
                               action: tool.action(for: arguments),
                               requiresApproval: AgentPolicy(maximumRisk: .external).requiresApproval(for: tool.descriptor.risk))
    }

    static func file(_ name: String, in root: String = yumi) -> ToolArguments { ["path": .string(root + "/" + name)] }
}

extension PermissionEvaluation {
    var approval: ApprovalRequest? {
        if case .ask(let approval) = self { return approval }
        return nil
    }

    var isAllow: Bool { self == .allow }

    var isDeny: Bool {
        if case .deny = self { return true }
        return false
    }
}
