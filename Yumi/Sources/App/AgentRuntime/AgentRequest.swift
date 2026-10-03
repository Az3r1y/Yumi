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
    /// The person chose to let the planner, and so a model, see the context. Off by default:
    /// the snapshot stays on the Mac (tools of this run may still read it). When on, only
    /// `RequestContext` leaves, and the runtime records a `contextShared` event first.
    var sharesContextWithModel: Bool
    /// The messages of the chat before this one, oldest first, so that a follow-up (« et
    /// demain ? ») can be understood. Words the person and Yumi exchanged, nothing from the screen.
    var conversation: [ConversationTurn]
    var timestamp: Date

    init(id: UUID = UUID(), userIntent: String, context: ContextSnapshot? = nil,
         sharesContextWithModel: Bool = false, conversation: [ConversationTurn] = [], timestamp: Date = Date()) {
        self.id = id
        self.userIntent = userIntent
        self.context = context
        self.sharesContextWithModel = sharesContextWithModel
        self.conversation = ConversationTurn.recent(conversation)
        self.timestamp = timestamp
    }

    /// The intent without surrounding spaces. Empty means there is nothing to do.
    var trimmedIntent: String { userIntent.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the planner may see of the context: nothing unless the person chose to share it.
    var contextForPlanner: RequestContext? { sharesContextWithModel ? RequestContext(context) : nil }
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

/// One message of the chat, as the planner may see it.
struct ConversationTurn: Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case person, yumi }
    var role: Role
    var text: String

    static let limit = 6
    static let maxCharacters = 400

    /// The last turns only, each one cut short: enough for a follow-up, not a transcript.
    static func recent(_ turns: [ConversationTurn]) -> [ConversationTurn] {
        turns.compactMap { turn in
            turn.text.nonEmptyTrimmed.map { ConversationTurn(role: turn.role, text: String($0.prefix(maxCharacters))) }
        }.suffix(limit).map { $0 }
    }
}
