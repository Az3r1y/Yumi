import Foundation

/// Everything that can stop or disturb a run. Values, never thrown past the runtime: a run
/// always ends with an `AgentResult`.
enum AgentError: Error, Equatable, Codable, Sendable {
    /// The intent is empty.
    case emptyIntent
    /// Another run is in progress.
    case busy
    /// No model is connected to plan with.
    case noProvider
    case providerFailed(String)
    /// The planner's answer is not a usable plan (bad JSON, unknown tool, wrong arguments…).
    case invalidPlan(String)
    /// The planner says the request cannot be done with the tools there are.
    case cannotPlan(String)
    /// The person asked to change something on the Mac that no tool can do: nothing runs, and
    /// the request is not passed on to anything else that could act.
    case unsupportedAction(String)
    case unknownTool(String)
    case invalidArguments(tool: String, reason: String)
    /// Known before asking: the tool cannot do it (a refused place, a folder Yumi cannot reach).
    /// Nobody was asked, nothing ran.
    case cannotRun(tool: String, reason: String)
    /// The tool is above what the policy lets the runtime do.
    case toolNotAllowed(tool: String, risk: ToolRisk)
    case toolFailed(tool: String, reason: String, transient: Bool)
    case toolTimedOut(tool: String)
    /// The tool answered, but not with what it promised (`ToolDescriptor.outputKeys`).
    case outputRejected(tool: String, reason: String)
    case permissionDenied(tool: String, reason: String?)
    /// Nobody answered the approval in time: nothing ran.
    case approvalExpired(tool: String)
    case verificationFailed(String)
    case cancelled

    /// One line for the debug panel and the traces.
    var message: String {
        switch self {
        case .emptyIntent: "Nothing was asked."
        case .busy: "Another task is running."
        case .noProvider: "No model is connected to plan with."
        case .providerFailed(let reason): "The model did not answer: \(reason)"
        case .invalidPlan(let reason): "The plan was refused: \(reason)"
        case .cannotPlan(let reason): "Cannot be done yet: \(reason)"
        case .unsupportedAction(let reason): "This action is not available yet: \(reason)"
        case .unknownTool(let tool): "Unknown tool \(tool)."
        case .invalidArguments(let tool, let reason): "Wrong arguments for \(tool): \(reason)"
        case .cannotRun(let tool, let reason): "\(tool) cannot run: \(reason)"
        case .toolNotAllowed(let tool, let risk): "\(tool) is not allowed (\(risk.rawValue))."
        case .toolFailed(let tool, let reason, _): "\(tool) failed: \(reason)"
        case .toolTimedOut(let tool): "\(tool) took too long."
        case .outputRejected(let tool, let reason): "\(tool) gave an unusable answer: \(reason)"
        case .permissionDenied(let tool, let reason): "Not allowed to use \(tool)" + (reason.map { ": \($0)" } ?? ".")
        case .approvalExpired(let tool): "Nobody approved \(tool) in time."
        case .verificationFailed(let reason): "Verification failed: \(reason)"
        case .cancelled: "Cancelled."
        }
    }
}
