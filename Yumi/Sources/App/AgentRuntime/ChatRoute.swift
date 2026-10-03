import Foundation

/// Where a chat message goes. The runtime takes what changes something on the Mac, so that it
/// goes through the permissions and is verified; talking, questions and reading stay with the
/// chat. Decided from the plan the runtime accepted, never from the words of the message.
enum ChatRoute: Equatable, Sendable {
    /// Run this plan: it acts on the Mac.
    case agent(AgentPlan)
    /// Answer as a conversation.
    case chat

    static func route(_ planned: Result<AgentPlan, AgentError>) -> ChatRoute {
        guard case .success(let plan) = planned, plan.estimatedRisk >= .write else { return .chat }
        return .agent(plan)
    }
}
