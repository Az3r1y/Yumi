import Foundation

/// How a run ended. Every run ends with one, whatever happened.
struct AgentResult: Equatable, Codable, Sendable {
    enum Status: String, Equatable, Codable, Sendable { case completed, failed, cancelled }

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

    /// The person has something to look at or decide: the work did not get done.
    var needsUser: Bool { status != .completed }
}
