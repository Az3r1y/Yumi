import Foundation

/// An agent is any external product that can drive sessions (Claude Code,
/// Cursor, a music app, …). The Core only knows the category, never the
/// concrete integration — adding a new agent must never require changing
/// the Core: connectors introduce themselves through events.
struct Agent: Hashable, Codable, Sendable, Identifiable {
    let id: AgentID
    var name: String
    var kind: AgentKind

    init(id: AgentID = AgentID(), name: String, kind: AgentKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Broad category of an agent. Open set: rawValue-based so new categories can
/// be added without breaking persisted data.
enum AgentKind: String, Codable, Sendable, CaseIterable {
    case coding
    case music
    case streaming
    case productivity
    case other
}
