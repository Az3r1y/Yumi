import Foundation

/// The single door between a plan and an action that needs the person's consent. The executor
/// calls it for every step that requires approval and runs the tool only on `.granted`; there
/// is no other path and no option to skip it.
///
/// The future Permission System implements this protocol: it shows the request, waits for the
/// person, remembers what they allowed. An implementation must return promptly when its task
/// is cancelled (the run is then cancelled whatever it answers).
protocol PermissionManager: Sendable {
    func authorize(_ request: AgentPermissionRequest) async -> PermissionDecision
}

/// Everything the person needs to decide, built by the executor from the registry and the
/// plan. The risk comes from the tool's code, never from the planner.
struct AgentPermissionRequest: Equatable, Codable, Sendable {
    var runID: UUID
    var stepID: String
    var goal: String
    /// The step's description: why the tool is needed.
    var reason: String
    var toolID: String
    var toolName: String
    var risk: ToolRisk
    var arguments: ToolArguments
}

enum PermissionDecision: Equatable, Sendable {
    case granted
    case denied(reason: String?)
}

/// Until the Permission System exists, nothing that needs approval runs: every request is
/// refused. Fail closed.
struct DenyingPermissionManager: PermissionManager {
    func authorize(_ request: AgentPermissionRequest) async -> PermissionDecision {
        .denied(reason: "Approvals are not available yet.")
    }
}
