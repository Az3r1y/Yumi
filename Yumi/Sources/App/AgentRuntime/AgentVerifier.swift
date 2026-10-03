import Foundation

/// Checks, once every step has run, that the work is really done. Replaceable: a later
/// verifier could ask a model whether the goal is met, but it can only refuse a result, never
/// run anything.
protocol AgentVerifier: Sendable {
    /// nil when the work is done, otherwise why not.
    func verify(_ task: RuntimeTask) async -> AgentError?
}

/// The checks that need no model: every step that had to run did, and gave an answer.
struct StructuralVerifier: AgentVerifier {
    func verify(_ task: RuntimeTask) async -> AgentError? {
        guard let plan = task.plan, !plan.steps.isEmpty else { return .verificationFailed("there is no plan") }
        for step in plan.steps {
            switch step.status {
            case .completed:
                if step.output == nil { return .verificationFailed("\(step.id) has no result") }
            case .skipped where step.isOptional:
                continue
            default:
                return .verificationFailed("\(step.id) is \(step.status.rawValue)")
            }
        }
        guard plan.steps.contains(where: { $0.status == .completed }) else {
            return .verificationFailed("no step was completed")
        }
        return nil
    }
}
