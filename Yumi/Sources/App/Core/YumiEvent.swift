import Foundation

/// A strongly typed event flowing through the engine.
///
/// This enum is THE contract between the outside world and Yumi: a connector
/// (Claude Code, Cursor, a music app, …) translates the specifics of its
/// product into `YumiEvent`s, and nothing else in Yumi ever needs to know
/// which product produced an event.
enum YumiEvent: Equatable, Sendable {
    /// A connector announces an agent it can represent.
    case agentRegistered(Agent)

    /// A new session started for the given agent.
    case sessionStarted(SessionID, Agent, title: String)

    /// A session ended (normally or not) and can be dropped.
    case sessionEnded(SessionID)

    /// The session started running a tool (command, file edit, search, …).
    case toolStarted(SessionID, ToolInfo)

    /// A previously started tool finished.
    case toolFinished(SessionID, ToolInfo)

    /// The session needs a permission decision before continuing.
    case permissionRequested(SessionID, PermissionRequest)

    /// The session asks the user a question.
    case questionRequested(SessionID, Question)

    /// The session finished its task successfully.
    case taskCompleted(SessionID)

    /// The session failed.
    case sessionErrored(SessionID, YumiError)

    /// Where the session runs. Sent again whenever it may have changed.
    case sessionLocated(SessionID, SessionOrigin)

    /// The user sent a prompt: the agent starts a turn.
    case promptSubmitted(SessionID, text: String)

    /// A pending permission request got its answer, from Yumi or from elsewhere.
    case permissionResolved(SessionID, requestID: String)

    /// The agent hit a usage limit.
    case rateLimited(SessionID)

    /// A line worth showing in the session's activity log. Changes no state.
    case activityNoted(SessionID, String)
}

extension YumiEvent {
    /// The session the event is about, if any.
    var sessionID: SessionID? {
        switch self {
        case .agentRegistered:
            return nil
        case .sessionStarted(let id, _, _), .sessionEnded(let id), .toolStarted(let id, _),
             .toolFinished(let id, _), .permissionRequested(let id, _), .questionRequested(let id, _),
             .taskCompleted(let id), .sessionErrored(let id, _), .sessionLocated(let id, _),
             .promptSubmitted(let id, _), .permissionResolved(let id, _), .rateLimited(let id),
             .activityNoted(let id, _):
            return id
        }
    }
}
