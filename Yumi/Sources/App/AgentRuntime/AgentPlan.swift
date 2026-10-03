import Foundation

/// A plan the runtime accepted: every step names a registered tool the policy allows, with
/// arguments that fit its schema. Built only by `PlanValidator`, so it can be shown and
/// inspected before anything runs.
struct AgentPlan: Equatable, Codable, Sendable {
    var goal: String
    var steps: [AgentStep]
    /// The highest risk among the tools of the plan, read from the registry.
    var estimatedRisk: ToolRisk
    /// The tools the plan uses, in order of first use.
    var requiredTools: [String]
    /// Which planner proposed it (`AgentPlanner.name`).
    var plannedBy: String

    var requiresApproval: Bool { steps.contains(where: \.requiresApproval) }
}

/// One step of a plan, and what became of it.
struct AgentStep: Identifiable, Equatable, Codable, Sendable {
    /// `step-1`, `step-2`… given by the runtime, never by the planner.
    let id: String
    var description: String
    var toolID: String
    var arguments: ToolArguments
    /// True when the policy says so for this tool's risk, or when the planner asked for it.
    /// A planner can add an approval, never remove one.
    var requiresApproval: Bool
    /// An optional step can be skipped when it fails or is refused; the plan goes on.
    var isOptional: Bool
    var status: StepStatus = .pending
    var attempts = 0
    var output: ToolOutput?
    var error: AgentError?

    init(id: String, description: String, toolID: String, arguments: ToolArguments = [:],
         requiresApproval: Bool = false, isOptional: Bool = false) {
        self.id = id
        self.description = description
        self.toolID = toolID
        self.arguments = arguments
        self.requiresApproval = requiresApproval
        self.isOptional = isOptional
    }
}

enum StepStatus: String, Equatable, Codable, Sendable {
    case pending, awaitingApproval, executing, completed, skipped, failed, cancelled

    /// The step will not change any more.
    var isFinished: Bool {
        switch self {
        case .completed, .skipped, .failed, .cancelled: true
        case .pending, .awaitingApproval, .executing: false
        }
    }
}

extension AgentPlan {
    /// A plan written by the developer, not by a model: each tool that needs no argument, once.
    /// Lets the debug panel check the executor end to end while no model is connected. It goes
    /// through `RuntimeAgent.execute`, so the registry, the policy and the permissions apply.
    static func toolCheck(_ tools: [ToolDescriptor]) -> AgentPlan? {
        let usable = tools.filter { $0.inputSchema.fields.allSatisfy { !$0.required } }
        guard !usable.isEmpty else { return nil }
        let steps = usable.enumerated().map { index, tool in
            AgentStep(id: "step-\(index + 1)", description: "Check \(tool.name)", toolID: tool.id)
        }
        return AgentPlan(goal: "Check the tools", steps: steps, estimatedRisk: usable.map(\.risk).max() ?? ToolRisk.none,
                         requiredTools: usable.map(\.id), plannedBy: "tool check")
    }
}
