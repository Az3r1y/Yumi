import Foundation

/// What one call of a tool really does, described by the tool's own code from its arguments.
/// The same tool can read a file (silent) or delete it (asks): permissions follow the action,
/// not the tool. A planner or a model never writes this: it comes from `Tool.action(for:)`.
struct ToolAction: Equatable, Codable, Sendable {
    var kind: ActionKind
    /// What the action touches. Empty when it touches nothing identifiable.
    var resources: [ResourceRef]
    /// False when the action cannot be undone (a sent email, a deleted file without a copy).
    var reversible: Bool
    /// The text the action writes, when the person should read it before agreeing (what is
    /// added to a file). Written by the tool from its arguments, shown as it is.
    var content: String?

    init(kind: ActionKind, resources: [ResourceRef] = [], reversible: Bool = true, content: String? = nil) {
        self.kind = kind
        self.resources = resources
        self.reversible = reversible
        self.content = content
    }
}

/// The verb of an action. Open to new cases; an unknown verb counts as risky.
enum ActionKind: String, Equatable, Codable, Sendable, CaseIterable {
    case read, create, modify, delete, run, send, publish, pay, other
}

/// Something an action touches.
struct ResourceRef: Hashable, Codable, Sendable {
    enum Kind: String, Hashable, Codable, Sendable {
        /// Yumi's own state: its context snapshot, its settings. Never the person's data.
        case yumi
        /// A file or a folder on this Mac. `identifier` is its path.
        case file
        /// A shell command. `identifier` is the command line.
        case command
        /// A page or an API outside the Mac. `identifier` is the URL.
        case url
        /// An account of an outside service: `identifier` names it ("gmail:me@example.com").
        case account
        /// Anything else. Never matched by a remembered permission.
        case unknown
    }

    var kind: Kind
    var identifier: String

    init(_ kind: Kind, _ identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    static func file(_ path: String) -> ResourceRef { ResourceRef(.file, path) }
}
