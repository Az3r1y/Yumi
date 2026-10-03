import Foundation

/// The work done for one request: its plan, where it stands, and how it ended.
struct RuntimeTask: Identifiable, Equatable, Codable, Sendable {
    /// The identifier of the run, in events and results.
    let id: UUID
    let request: AgentRequest
    var plan: AgentPlan?
    var state: ExecutionState
    /// The step being worked on, nil before the first one and after the last.
    var currentStepIndex: Int?
    let startedAt: Date
    var finishedAt: Date?
    var result: AgentResult?

    init(id: UUID = UUID(), request: AgentRequest, startedAt: Date) {
        self.id = id
        self.request = request
        self.startedAt = startedAt
        state = .planning
    }

    var currentStep: AgentStep? {
        guard let index = currentStepIndex, let plan, plan.steps.indices.contains(index) else { return nil }
        return plan.steps[index]
    }

    /// Finished steps over all steps, 0 to 1. 0 without a plan.
    var progress: Double {
        guard let steps = plan?.steps, !steps.isEmpty else { return 0 }
        return Double(steps.filter { $0.status.isFinished }.count) / Double(steps.count)
    }
}

/// The record of one run: the task and every event, in order. What a future replay, history or
/// timeline reads. Kept in memory only.
struct AgentRun: Identifiable, Equatable, Codable, Sendable {
    static let eventLimit = 200

    var task: RuntimeTask
    private(set) var events: [AgentEvent] = []

    init(task: RuntimeTask) { self.task = task }

    var id: UUID { task.id }
    var startedAt: Date { task.startedAt }
    var completedAt: Date? { task.finishedAt }
    var goal: String? { task.plan?.goal }
    var steps: [AgentStep] { task.plan?.steps ?? [] }
    var result: AgentResult? { task.result }
    var status: ExecutionState { task.state }

    /// Keeps the first events (how it started) and the last ones (how it ended) when a run
    /// produces more than the limit.
    mutating func append(_ event: AgentEvent) {
        events.append(event)
        if events.count > Self.eventLimit { events.remove(at: Self.eventLimit / 2) }
    }
}

/// The last runs, most recent first. In memory only: nothing about what the person asked is
/// written to disk.
struct AgentRunHistory: Equatable, Sendable {
    let capacity: Int
    private(set) var runs: [AgentRun] = []

    init(capacity: Int = 20) { self.capacity = max(1, capacity) }

    mutating func record(_ run: AgentRun) {
        runs.removeAll { $0.id == run.id }
        runs.insert(run, at: 0)
        if runs.count > capacity { runs.removeLast(runs.count - capacity) }
    }

    func run(id: UUID) -> AgentRun? { runs.first { $0.id == id } }
}

extension RuntimeTask {
    /// Ends the task: steps that will not run any more are marked cancelled, the state and the
    /// result are written.
    mutating func finish(_ status: AgentResult.Status, error: AgentError?, at date: Date) {
        if var plan {
            for index in plan.steps.indices where !plan.steps[index].status.isFinished {
                plan.steps[index].status = .cancelled
            }
            self.plan = plan
        }
        currentStepIndex = nil
        finishedAt = date
        state = switch status {
        case .completed, .partial: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        }
        result = AgentResult(runID: id, status: status, goal: plan?.goal, steps: plan?.steps ?? [],
                             error: error, finishedAt: date)
    }
}
