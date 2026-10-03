import Foundation
import Observation

/// Yumi's agent runtime: a request goes in, an `AgentResult` comes out.
///
/// Request → plan (proposed by the planner, accepted by `PlanValidator`) → steps run by the
/// `AgentExecutor`, each one through the policy and, when needed, the `PermissionManager` →
/// verification → result. Every change is published as an `AgentEvent` and recorded in the
/// run's history.
///
/// It does nothing by itself: no timer, no watching, no context capture. It works only when
/// asked, one run at a time. Named `RuntimeAgent` because `Agent` (Core/) already means an
/// external product driving sessions, such as Claude Code.
@MainActor
@Observable
final class RuntimeAgent {
    /// The run in progress, or the last one. nil before the first run.
    private(set) var current: AgentRun?
    private(set) var history: AgentRunHistory
    private(set) var isRunning = false

    var state: ExecutionState { current?.task.state ?? .idle }
    var activity: AgentActivity { state.activity }

    @ObservationIgnored let planner: any AgentPlanner
    @ObservationIgnored let tools: ToolRegistry
    @ObservationIgnored let policy: AgentPolicy
    @ObservationIgnored private let executor: AgentExecutor
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var runningTask: Task<AgentResult, Never>?
    @ObservationIgnored private var nextEventID = 1
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<AgentEvent>.Continuation] = [:]

    /// - Parameters:
    ///   - permissions: refuses everything by default, until the Permission System exists.
    ///   - sleep: the wait before a retry, injected by the tests.
    init(planner: any AgentPlanner,
         tools: ToolRegistry = .standard,
         permissions: any PermissionManager = DenyingPermissionManager(),
         policy: AgentPolicy = AgentPolicy(),
         recovery: RecoveryPolicy = RecoveryPolicy(),
         verifier: any AgentVerifier = StructuralVerifier(),
         historyCapacity: Int = 20,
         clock: @escaping @Sendable () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.planner = planner
        self.tools = tools
        self.policy = policy
        self.clock = clock
        history = AgentRunHistory(capacity: historyCapacity)
        executor = AgentExecutor(tools: tools, permissions: permissions, policy: policy, recovery: recovery,
                                 verifier: verifier, clock: clock, sleep: sleep)
    }

    /// The tools a plan may use: registered, and allowed by the policy.
    var availableTools: [ToolDescriptor] { tools.descriptors(allowedBy: policy) }

    // MARK: - Subscribing

    /// Every event from now on. The stream ends when the subscriber stops iterating.
    func events() -> AsyncStream<AgentEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self, bufferingPolicy: .bufferingNewest(128))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    // MARK: - Working

    /// Asks the planner and checks its proposal, without running anything and without
    /// recording a run: the plan can be shown before `execute(_:for:)`.
    func plan(for request: AgentRequest) async -> Result<AgentPlan, AgentError> {
        do throws(AgentError) {
            return .success(try await makePlan(for: request))
        } catch {
            return .failure(error)
        }
    }

    /// Plans, runs and verifies. Returns when the run is over.
    func run(_ request: AgentRequest) async -> AgentResult {
        await start(request, plan: nil)
    }

    /// Runs a plan obtained earlier. It is checked again against the registry and the policy:
    /// a plan kept or changed since cannot skip a rule.
    func execute(_ plan: AgentPlan, for request: AgentRequest) async -> AgentResult {
        await start(request, plan: plan)
    }

    /// Stops the run in progress. It ends as cancelled at the next safe point.
    func cancel() {
        runningTask?.cancel()
    }

    // MARK: - Private

    private func start(_ request: AgentRequest, plan: AgentPlan?) async -> AgentResult {
        guard runningTask == nil else {
            return AgentResult(runID: UUID(), status: .failed, goal: nil, steps: [], error: .busy, finishedAt: clock())
        }
        let work = Task { await self.perform(request, plan: plan) }
        runningTask = work
        isRunning = true
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        runningTask = nil
        isRunning = false
        return result
    }

    private func perform(_ request: AgentRequest, plan given: AgentPlan?) async -> AgentResult {
        var task = RuntimeTask(request: request, startedAt: clock())
        current = AgentRun(task: task)
        publish(task, .agentStarted(intent: request.trimmedIntent))

        do throws(AgentError) {
            if let given {
                guard request.trimmedIntent.nonEmptyTrimmed != nil else { throw .emptyIntent }
                task.plan = try PlanValidator.revalidate(given, registry: tools, policy: policy)
            } else {
                task.plan = try await makePlan(for: request)
            }
            if Task.isCancelled { throw .cancelled }
        } catch {
            let cancelled = Task.isCancelled || error == .cancelled
            task.finish(cancelled ? .cancelled : .failed, error: cancelled ? .cancelled : error, at: clock())
            return close(task)
        }

        let plan = task.plan!
        publish(task, .planCreated(goal: plan.goal, steps: plan.steps.count, risk: plan.estimatedRisk))
        let ended = await executor.execute(task) { [weak self] task, kind in self?.publish(task, kind) }
        return close(ended)
    }

    private func makePlan(for request: AgentRequest) async throws(AgentError) -> AgentPlan {
        guard request.trimmedIntent.nonEmptyTrimmed != nil else { throw .emptyIntent }
        let proposal = try await planner.propose(for: request, tools: availableTools)
        if Task.isCancelled { throw .cancelled }
        return try PlanValidator.validate(proposal, registry: tools, policy: policy, plannedBy: planner.name)
    }

    /// Publishes the terminal event and keeps the run in the history.
    private func close(_ task: RuntimeTask) -> AgentResult {
        let result = task.result ?? AgentResult(runID: task.id, status: .failed, goal: task.plan?.goal,
                                                steps: task.plan?.steps ?? [], error: nil, finishedAt: clock())
        let event: AgentEvent.Kind = switch result.status {
        case .completed: .agentCompleted(summary: result.summary)
        case .failed: .agentFailed(result.error ?? .verificationFailed("unknown"))
        case .cancelled: .agentCancelled(reason: result.error ?? .cancelled)
        }
        publish(task, event)
        if let current { history.record(current) }
        return result
    }

    private func publish(_ task: RuntimeTask, _ kind: AgentEvent.Kind?) {
        guard current?.id == task.id else { return }
        current?.task = task
        guard let kind else { return }
        let event = AgentEvent(id: nextEventID, runID: task.id, date: clock(), kind: kind)
        nextEventID += 1
        current?.append(event)
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
