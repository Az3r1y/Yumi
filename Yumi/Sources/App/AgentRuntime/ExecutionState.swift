import Foundation

/// Where a run stands.
enum ExecutionState: String, Equatable, Codable, Sendable {
    case idle
    case planning
    case awaitingApproval
    case executing
    case verifying
    case completed
    case failed
    case cancelled

    var isFinished: Bool { self == .completed || self == .failed || self == .cancelled }

    /// What the runtime is doing, in words the character layer can draw. The runtime says
    /// nothing about poses, moods or habits: the character decides how each one looks.
    var activity: AgentActivity {
        switch self {
        case .idle, .cancelled: .idle
        case .planning: .planning
        case .executing: .working
        case .awaitingApproval: .waiting
        case .verifying: .thinking
        case .completed: .success
        case .failed: .error
        }
    }
}

/// The runtime's state as the character could show it.
enum AgentActivity: String, Equatable, Codable, Sendable, CaseIterable {
    case idle, thinking, planning, working, waiting, success, error
}
