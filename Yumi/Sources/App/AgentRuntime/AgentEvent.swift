import Foundation

/// Something that happened during a run. Events describe; they do not ask for anything to be
/// shown. Whether Yumi reacts, and how, is for the layer that listens to decide
/// (`suggestedPriority` is only a hint).
struct AgentEvent: Identifiable, Equatable, Codable, Sendable {
    /// Increases with every event of one runtime.
    let id: Int
    let runID: UUID
    let date: Date
    let kind: Kind

    enum Kind: Equatable, Codable, Sendable {
        case agentStarted(intent: String)
        case planCreated(goal: String, steps: Int, risk: ToolRisk)
        case stepStarted(stepID: String, attempt: Int)
        case stepCompleted(stepID: String, summary: String)
        case stepFailed(stepID: String, error: AgentError, recovery: RecoveryAction)
        case stepSkipped(stepID: String)
        case approvalRequired(AgentPermissionRequest)
        case approvalGranted(stepID: String)
        case approvalDenied(stepID: String, reason: String?)
        case approvalExpired(stepID: String)
        case verificationStarted
        case agentCompleted(summary: String)
        case agentFailed(AgentError)
        case agentCancelled(reason: AgentError)
    }

    /// One word for the debug panel and the traces.
    var name: String {
        switch kind {
        case .agentStarted: "agentStarted"
        case .planCreated: "planCreated"
        case .stepStarted: "stepStarted"
        case .stepCompleted: "stepCompleted"
        case .stepFailed: "stepFailed"
        case .stepSkipped: "stepSkipped"
        case .approvalRequired: "approvalRequired"
        case .approvalGranted: "approvalGranted"
        case .approvalDenied: "approvalDenied"
        case .approvalExpired: "approvalExpired"
        case .verificationStarted: "verificationStarted"
        case .agentCompleted: "agentCompleted"
        case .agentFailed: "agentFailed"
        case .agentCancelled: "agentCancelled"
        }
    }

    /// A line for the debug panel.
    var summary: String {
        switch kind {
        case .agentStarted(let intent): "Agent started: \(intent)"
        case .planCreated(let goal, let steps, _): "Plan created: \(goal) (\(steps) step\(steps == 1 ? "" : "s"))"
        case .stepStarted(let id, let attempt): attempt > 1 ? "\(id) started, try \(attempt)" : "\(id) started"
        case .stepCompleted(let id, let summary): "\(id) completed: \(summary)"
        case .stepFailed(let id, let error, let recovery): "\(id) failed (\(recovery.rawValue)): \(error.message)"
        case .stepSkipped(let id): "\(id) skipped"
        case .approvalRequired(let request): "Approval required: \(request.toolName)"
        case .approvalGranted(let id): "\(id) approved"
        case .approvalDenied(let id, _): "\(id) refused"
        case .approvalExpired(let id): "\(id) not answered in time"
        case .verificationStarted: "Verification started"
        case .agentCompleted: "Agent completed"
        case .agentFailed(let error): "Agent failed: \(error.message)"
        case .agentCancelled(let reason): "Agent cancelled: \(reason.message)"
        }
    }

    /// How much this event could deserve the person's attention. A hint for the UX layer,
    /// which stays free to show nothing.
    var suggestedPriority: InteractionPriority {
        switch kind {
        case .agentStarted, .planCreated, .stepStarted, .stepCompleted, .stepSkipped,
             .approvalGranted, .verificationStarted:
            .silent
        case .stepFailed(_, _, let recovery):
            recovery == .retry || recovery == .skip ? .silent : .ambient
        case .approvalDenied, .approvalExpired, .agentCompleted, .agentCancelled:
            .ambient
        case .agentFailed:
            .attention
        case .approvalRequired:
            .blocking
        }
    }
}

/// How strongly something may interrupt the person.
enum InteractionPriority: Int, Equatable, Codable, Sendable, Comparable, CaseIterable {
    /// Nothing visible.
    case silent
    /// A small reaction of Yumi at most, no text.
    case ambient
    /// Worth a word, when the person is not busy.
    case attention
    /// Nothing goes on without the person.
    case blocking

    static func < (lhs: InteractionPriority, rhs: InteractionPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}
