import Foundation

/// The rules the runtime applies to every plan, whoever proposed it. Set by the code that
/// creates the runtime; a plan, a model or a tool cannot change them.
struct AgentPolicy: Equatable, Sendable {
    /// Tools above this risk are never run, approved or not. Today Yumi only reads.
    var maximumRisk: ToolRisk = .read
    /// From this risk on, a step asks the person first. Cannot be set above `.write`:
    /// changing something or leaving the Mac always asks (`requiresApproval(for:)`).
    var approvalThreshold: ToolRisk = .write
    /// A longer plan is refused.
    var maxSteps = 12

    func allows(_ risk: ToolRisk) -> Bool { risk <= maximumRisk }

    func requiresApproval(for risk: ToolRisk) -> Bool {
        risk >= min(approvalThreshold, .write)
    }
}

/// What to do after a step failed.
enum RecoveryAction: String, Equatable, Codable, Sendable {
    /// Run the step again.
    case retry
    /// Leave it and go on with the next one. Only for an optional step.
    case skip
    /// Stop the run as cancelled: the person said no.
    case cancel
    /// Stop the run as failed.
    case fail
}

/// How hard the runtime tries before giving up. The limits are clamped: a policy cannot ask
/// for endless retries.
struct RecoveryPolicy: Equatable, Sendable {
    /// Tries of one step, the first one included. 1...5.
    var maxAttempts: Int { didSet { maxAttempts = Self.clamp(maxAttempts, 1...5) } }
    /// Retries for a whole run, all steps together. 0...20.
    var maxRetriesPerRun: Int { didSet { maxRetriesPerRun = Self.clamp(maxRetriesPerRun, 0...20) } }
    /// Wait before a retry, multiplied by the number of tries so far.
    var retryDelay: Duration
    /// A tool that takes longer is stopped and counts as timed out.
    var stepTimeout: Duration

    init(maxAttempts: Int = 3, maxRetriesPerRun: Int = 6,
         retryDelay: Duration = .milliseconds(500), stepTimeout: Duration = .seconds(30)) {
        self.maxAttempts = Self.clamp(maxAttempts, 1...5)
        self.maxRetriesPerRun = Self.clamp(maxRetriesPerRun, 0...20)
        self.retryDelay = retryDelay
        self.stepTimeout = stepTimeout
    }

    /// - Parameters:
    ///   - attempt: the try that just failed, from 1.
    ///   - retriesUsed: retries already spent in this run.
    func decide(after error: AgentError, attempt: Int, retriesUsed: Int, optional: Bool) -> RecoveryAction {
        let giveUp: RecoveryAction = optional ? .skip : .fail
        switch error {
        case .cancelled:
            return .cancel
        case .permissionDenied:
            return optional ? .skip : .cancel
        case .toolTimedOut, .toolFailed(_, _, transient: true):
            return attempt < maxAttempts && retriesUsed < maxRetriesPerRun ? .retry : giveUp
        default:
            return giveUp
        }
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
