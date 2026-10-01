import Foundation

// MARK: - Typed identifiers
//
// Each identifier is a tiny wrapper around String. This is deliberate: passing
// a `SessionID` where an `AgentID` is expected is a compile-time error, which
// plain strings would silently allow. Every identifier can be created from a
// known value (`SessionID("claude-session-1")`) or generated uniquely (`SessionID()`).

/// Identifies an agent (the product that runs sessions: a coding agent, a
/// music app, …).
struct AgentID: Hashable, Codable, Sendable, CustomStringConvertible {
    let value: String

    /// Creates an agent ID from a known value (e.g. "claude-code").
    init(_ value: String) { self.value = value }

    /// Creates a unique agent ID.
    init() { self.value = UUID().uuidString }

    var description: String { value }
}

/// Identifies one session: one run of one agent (e.g. one Claude Code
/// conversation). Two agents can run sessions at the same time without any
/// ambiguity, and the Core never needs to know which product they belong to.
struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    let value: String

    /// Creates a session ID from a known value (e.g. the source session key).
    init(_ value: String) { self.value = value }

    /// Creates a unique session ID.
    init() { self.value = UUID().uuidString }

    var description: String { value }
}

/// Identifies a single event instance (useful for tracing/debugging later).
struct EventID: Hashable, Codable, Sendable, CustomStringConvertible {
    let value: String

    init() { self.value = UUID().uuidString }

    var description: String { value }
}
