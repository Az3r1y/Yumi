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
}
