import Foundation

/// The single door between a plan and an action. The executor asks it about every step, before
/// the tool runs, whatever the step's risk: there is no other path and no option to skip it.
///
/// `evaluate` answers at once: allow (silently), ask (an `ApprovalRequest` the person will see),
/// or deny. On ask, `decision(on:)` waits for the person. The runtime only knows these outcomes;
/// how permissions are stored and remembered is the implementation's business
/// (`LocalPermissionManager`, in Permissions/).
///
/// An implementation must return promptly when its task is cancelled (the run is then cancelled
/// whatever it answers).
protocol PermissionManager: Sendable {
    /// - Parameter upcoming: the steps of the same run that come after this one, so that similar
    ///   actions can be approved together. Information only: nothing in it is allowed by itself.
    func evaluate(_ request: AgentPermissionRequest, upcoming: [AgentPermissionRequest]) async -> PermissionEvaluation
    /// Waits for the person's answer to an approval `evaluate` returned.
    func decision(on approval: ApprovalRequest) async -> PermissionDecision
    /// The run is over, however it ended: what was pending is cancelled, and what was allowed
    /// for this run only can no longer be used.
    func finishRun(_ runID: UUID) async
}

/// Everything the permission system knows about a step, built by the executor from the
/// registry, the tool's code and the plan. The risk and the action come from the tool, never
/// from the planner. There is no context snapshot here on purpose: what is on screen helps to
/// understand a request, it never allows anything.
struct AgentPermissionRequest: Equatable, Codable, Sendable {
    var runID: UUID
    var stepID: String
    var goal: String
    /// The step's description: why the tool is needed. Written by the planner: shown, never trusted.
    var reason: String
    var toolID: String
    var toolName: String
    var risk: ToolRisk
    var arguments: ToolArguments
    /// What this call does, from `Tool.action(for:)`. nil when the tool cannot say.
    var action: ToolAction? = nil
    /// The runtime's policy or the plan wants the person's consent for this step. Consent can
    /// be an answer now, or one the person gave before for exactly this scope.
    var requiresApproval: Bool = true

    /// The same tool with the same arguments: one exact action.
    var fingerprint: String {
        toolID + "(" + arguments.keys.sorted().map { "\($0)=\(arguments[$0]!.description)" }.joined(separator: ",") + ")"
    }
}

/// What the permission system says about a step before anything runs.
enum PermissionEvaluation: Equatable, Sendable {
    /// Run it, nothing to show.
    case allow
    /// The person decides: wait on `PermissionManager.decision(on:)`.
    case ask(ApprovalRequest)
    /// Never. Not even with an approval.
    case deny(reason: String)
}

/// How an approval ended, as the runtime sees it.
enum PermissionDecision: Equatable, Sendable {
    case granted
    case denied(reason: String?)
    /// Nobody answered in time. Nothing runs; asking again means a new request.
    case expired
    /// The run or the request was cancelled before an answer.
    case cancelled
}

/// The runtime's default when no permission system is given: what needs consent is refused,
/// the rest runs. Fail closed.
struct DenyingPermissionManager: PermissionManager {
    func evaluate(_ request: AgentPermissionRequest, upcoming: [AgentPermissionRequest]) async -> PermissionEvaluation {
        request.requiresApproval ? .deny(reason: "Approvals are not available.") : .allow
    }

    func decision(on approval: ApprovalRequest) async -> PermissionDecision {
        .denied(reason: "Approvals are not available.")
    }

    func finishRun(_ runID: UUID) async {}
}
