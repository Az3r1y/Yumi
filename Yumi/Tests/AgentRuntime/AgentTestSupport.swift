import Foundation

// Test doubles for the agent runtime. None of them exists in the app: the product has no
// scripted model and no permission manager that says yes.

final class AgentTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

/// A model that answers what the test wrote, and remembers what it was asked.
final class ScriptedLLMProvider: LLMProvider, @unchecked Sendable {
    enum Answer {
        case text(String)
        case error(Error)
        /// Never answers until cancelled.
        case hang
    }

    let name: String
    private let lock = NSLock()
    private var answers: [Answer]
    private var received: [LLMRequest] = []

    init(name: String = "scripted", _ answers: [Answer]) {
        self.name = name
        self.answers = answers
    }

    convenience init(json: String) { self.init([.text(json)]) }

    var requests: [LLMRequest] { lock.withLock { received } }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let answer: Answer = lock.withLock {
            received.append(request)
            return answers.isEmpty ? .error(LLMProviderError.failed("no more answers")) : answers.removeFirst()
        }
        switch answer {
        case .text(let text): return LLMResponse(text: text)
        case .error(let error): throw error
        case .hang:
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }
    }
}

/// A tool whose behaviour the test writes, call after call.
final class FakeTool: Tool, @unchecked Sendable {
    enum Outcome {
        case output(ToolOutput)
        case error(Error)
        /// Never answers until cancelled.
        case hang
    }

    let descriptor: ToolDescriptor
    private let lock = NSLock()
    private var outcomes: [Outcome]
    private let fallback: Outcome
    private var count = 0
    private let log: CallLog?

    init(id: String, risk: ToolRisk = .none, schema: ToolInputSchema = .empty, outputKeys: [String] = [],
         outcomes: [Outcome] = [], fallback: Outcome? = nil, log: CallLog? = nil) {
        descriptor = ToolDescriptor(id: id, name: id, description: "A tool for the tests.", inputSchema: schema,
                                    risk: risk, outputKeys: outputKeys)
        self.outcomes = outcomes
        self.fallback = fallback ?? .output(ToolOutput(summary: "\(id) done", values: Dictionary(uniqueKeysWithValues: outputKeys.map { ($0, .bool(true)) })))
        self.log = log
    }

    var calls: Int { lock.withLock { count } }
    /// What `verify` answers: nil, the effect is there.
    var effectProblem: String? {
        get { lock.withLock { problem } }
        set { lock.withLock { problem = newValue } }
    }
    private var problem: String?

    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? { effectProblem }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let outcome: Outcome = lock.withLock {
            count += 1
            return outcomes.isEmpty ? fallback : outcomes.removeFirst()
        }
        log?.append(descriptor.id)
        switch outcome {
        case .output(let output): return output
        case .error(let error): throw error
        case .hang:
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }
    }
}

/// The order tools were called in.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var calls: [String] { lock.withLock { entries } }
}

/// Answers permission requests as the test wrote, and remembers them. Steps that need no
/// consent are allowed without using the script, like the real manager does for safe ones.
final class ScriptedPermissionManager: PermissionManager, @unchecked Sendable {
    enum Answer {
        case decision(PermissionDecision)
        case hang
    }

    private let lock = NSLock()
    private var answers: [Answer]
    private var received: [AgentPermissionRequest] = []
    private var finished: [UUID] = []

    init(_ answers: [Answer]) { self.answers = answers }

    var requests: [AgentPermissionRequest] { lock.withLock { received } }
    var finishedRuns: [UUID] { lock.withLock { finished } }

    func evaluate(_ request: AgentPermissionRequest, upcoming: [AgentPermissionRequest]) async -> PermissionEvaluation {
        guard request.requiresApproval else { return .allow }
        lock.withLock { received.append(request) }
        return .ask(ApprovalRequest(agentRunID: request.runID, toolID: request.toolID, toolName: request.toolName,
                                    action: request.action?.kind, goal: request.goal, reason: request.reason,
                                    riskLevel: RiskLevel(request.risk), resources: [], container: nil, reversible: true,
                                    items: [], createdAt: Date(), expiresAt: Date().addingTimeInterval(60)))
    }

    func decision(on approval: ApprovalRequest) async -> PermissionDecision {
        let answer: Answer = lock.withLock { answers.isEmpty ? .decision(.denied(reason: "unscripted")) : answers.removeFirst() }
        switch answer {
        case .decision(let decision): return decision
        case .hang:
            try? await Task.sleep(for: .seconds(600))
            return .cancelled
        }
    }

    func finishRun(_ runID: UUID) async { lock.withLock { finished.append(runID) } }
}

/// A plan as a model would write it.
func planJSON(goal: String = "Test goal", _ steps: [(tool: String, optional: Bool)]) -> String {
    let items = steps.enumerated().map { index, step in
        #"{"description": "Step \#(index + 1)", "tool": "\#(step.tool)", "arguments": {}, "optional": \#(step.optional)}"#
    }
    return #"{"goal": "\#(goal)", "steps": [\#(items.joined(separator: ", "))]}"#
}

func planJSON(goal: String = "Test goal", tools: [String]) -> String {
    planJSON(goal: goal, tools.map { ($0, false) })
}

/// A context snapshot of someone working in an editor.
func editorSnapshot(windowTitle: String = "main.swift (Yumi)", documentPath: String? = "/Users/someone/yumi/Sources/main.swift") -> ContextSnapshot {
    var snapshot = ContextSnapshot.disabled(at: Date(timeIntervalSince1970: 1_790_000_000))
    snapshot.isEnabled = true
    snapshot.presence = .observing
    snapshot.accessibility = .granted
    snapshot.activeApplication = ApplicationContext(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", processID: 101,
                                                    category: ApplicationCategory("public.app-category.developer-tools"))
    snapshot.activeWindow = WindowContext(title: windowTitle, processID: 101, documentPath: documentPath)
    snapshot.previousApplication = ApplicationContext(bundleID: "com.apple.Terminal", name: "Terminal", processID: 102)
    snapshot.recentApplications = [ApplicationContext(bundleID: "com.example.private", name: "PrivateDiary", processID: 103)]
    return snapshot
}

/// Waits a little for something asynchronous, without a fixed sleep.
@MainActor
func eventuallyTrue(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
