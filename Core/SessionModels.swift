import Foundation

// MARK: - Session lifecycle status

/// Lifecycle of one session.
enum SessionStatus: Equatable, Codable, Sendable {
    case running
    case waitingForUser
    case errored
    case completed
}

// MARK: - Current activity

/// What the agent is doing right now inside a session.
enum YumiActivity: Equatable, Codable, Sendable {
    case idle
    case working(ToolInfo)
    case asking(Question)
    case requestingPermission(PermissionRequest)
}

// MARK: - Event payloads

/// A tool invocation (command run, file edit, search, …).
struct ToolInfo: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var name: String
    var summary: String

    init(id: String = UUID().uuidString, name: String, summary: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// A permission the agent needs before continuing (e.g. run a command).
struct PermissionRequest: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var tool: String
    var command: String

    init(id: String = UUID().uuidString, tool: String, command: String = "") {
        self.id = id
        self.tool = tool
        self.command = command
    }
}

/// A question the agent asks the user.
struct Question: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var text: String
    var options: [String]

    init(id: String = UUID().uuidString, text: String, options: [String] = []) {
        self.id = id
        self.text = text
        self.options = options
    }
}

/// An error reported by a session.
struct YumiError: Equatable, Codable, Sendable {
    var message: String

    init(message: String) { self.message = message }
}

// MARK: - Session

/// One session = one run of an agent (e.g. one Claude Code conversation).
/// A plain value type: the store owns all sessions, events transform them.
struct Session: Equatable, Codable, Sendable, Identifiable {
    let id: SessionID
    let agent: Agent
    var title: String
    var status: SessionStatus
    var activity: YumiActivity

    init(id: SessionID = SessionID(), agent: Agent, title: String) {
        self.id = id
        self.agent = agent
        self.title = title
        self.status = .running
        self.activity = .idle
    }
}
