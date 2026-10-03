import Foundation

/// How a run ended. Every run ends with one, whatever happened.
struct AgentResult: Equatable, Codable, Sendable {
    enum Status: String, Equatable, Codable, Sendable {
        /// Every step ran and was verified.
        case completed
        /// Every required step ran and was verified; at least one optional step was left out.
        case partial
        case failed, cancelled

        /// Something real was done and checked.
        var succeeded: Bool { self == .completed || self == .partial }
    }

    var runID: UUID
    var status: Status
    var goal: String?
    /// The steps as they ended, outputs and errors included. Empty when no plan was made.
    var steps: [AgentStep]
    /// Why the run did not complete. nil when it did.
    var error: AgentError?
    var finishedAt: Date

    /// What the completed steps found, one line each.
    var summary: String {
        steps.compactMap { $0.status == .completed ? $0.output?.summary : nil }.joined(separator: "\n")
    }

    /// The person has something to look at or decide: the work did not all get done.
    var needsUser: Bool { status != .completed }
}
