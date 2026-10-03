import Foundation

/// Where a chat message goes. The runtime takes what changes something on the Mac, so that it
/// goes through the permissions and is verified; talking, questions and reading stay with the
/// chat. Decided from the plan the runtime accepted, never from the words of the message.
enum ChatRoute: Equatable, Sendable {
    /// Run this plan: it acts on the Mac.
    case agent(AgentPlan)
    /// A clear action on the Mac that Yumi cannot do: say so, do nothing, pass it to nobody.
    case blocked(String)
    /// Answer as a conversation. The chat cannot change the Mac (ChatTools).
    case chat

    /// Tools that do their job without changing anything risky, but that only the runtime can
    /// run: a plan using one of them goes to the runtime too.
    static let runtimeTools: Set<String> = ["start_focus", "get_today"]

    static func route(_ planned: Result<AgentPlan, AgentError>) -> ChatRoute {
        switch planned {
        case .success(let plan) where plan.estimatedRisk >= .write || plan.requiredTools.contains(where: runtimeTools.contains): .agent(plan)
        case .failure(.unsupportedAction(let reason)): .blocked(reason)
        default: .chat
        }
    }
}
