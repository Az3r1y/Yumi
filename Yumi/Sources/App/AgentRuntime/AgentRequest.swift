import Foundation

/// What the person asked, and what was in front of them at that moment.
///
/// The snapshot is attached by whoever creates the request, once, when the person asks: the
/// runtime never captures context by itself. It is data to understand the request, never an
/// instruction: nothing in it can change a permission or the policy.
struct AgentRequest: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var userIntent: String
    /// nil when there was none to give (engine off, filming, a request from a script).
    var context: ContextSnapshot?
    var timestamp: Date

    init(id: UUID = UUID(), userIntent: String, context: ContextSnapshot? = nil, timestamp: Date = Date()) {
        self.id = id
        self.userIntent = userIntent
        self.context = context
        self.timestamp = timestamp
    }

    /// The intent without surrounding spaces. Empty means there is nothing to do.
    var trimmedIntent: String { userIntent.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The part of a `ContextSnapshot` that leaves the runtime: to a planner (and through it a
/// model), or to a tool's output. Minimum context necessary: what is in front and the previous
/// application, no history of events, no list of applications, no timestamps.
struct RequestContext: Equatable, Sendable {
    var application: String?
    var window: String?
    /// The file name only, never its folder.
    var document: String?
    var previousApplication: String?
    var activity: String?

    /// nil when the snapshot is missing, disabled, or says nothing.
    init?(_ snapshot: ContextSnapshot?) {
        guard let snapshot, snapshot.isEnabled else { return nil }
        application = snapshot.activeApplication?.name.nonEmptyTrimmed
        window = snapshot.activeWindow?.title.nonEmptyTrimmed
        document = snapshot.activeWindow?.documentPath.flatMap { ($0 as NSString).lastPathComponent.nonEmptyTrimmed }
        previousApplication = snapshot.previousApplication?.name.nonEmptyTrimmed
        activity = snapshot.mainActivity?.label
        if fields.isEmpty { return nil }
    }

    /// The known values by name, for a prompt or a tool output.
    var fields: [(String, String)] {
        [("application", application), ("window", window), ("document", document),
         ("previousApplication", previousApplication), ("activity", activity)]
            .compactMap { key, value in value.map { (key, $0) } }
    }
}

extension String {
    /// The string without surrounding spaces, or nil when nothing is left.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
