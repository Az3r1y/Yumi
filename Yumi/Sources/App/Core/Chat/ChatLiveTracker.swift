import Foundation

/// Builds the `ChatLive` the island shows from what Claude Code says while it answers
/// (Contracts/ChatLive.swift). Pure: events in, a value out.
struct ChatLiveTracker: Sendable {
    /// Lines and width an action's preview is cut to.
    static let previewLines = 4
    static let previewWidth = 80

    private(set) var live = ChatLive()

    /// Actions under way, oldest first. Several tools can be named at once; the island shows one.
    private var running: [ChatActivity] = []
    /// What each action was before it started waiting for a permission.
    private var beforeWaiting: [String: ChatActivity] = [:]
    private var refused: Set<String> = []
    /// Everything written in the current message, memory block included.
    private var written = ""

    mutating func apply(_ event: ChatStreamEvent) {
        switch event {
        case .started, .permissionCancelled, .finished:
            break

        case .messageStarted:
            written = ""
            live.text = ""

        case .textDelta(let words):
            written += words
            // The memory block at the end of an answer is not for the person.
            live.text = MemoryNotes.visible(whileWriting: written)

        case .text(let text):
            written = text
            live.text = MemoryNotes.visible(whileWriting: text)

        case .toolAnnounced(let id, let name):
            guard !running.contains(where: { $0.id == id }) else { break }
            running.append(Self.activity(for: ChatToolUse(id: id, name: name, detail: "")))

        case .toolStarted(let tool):
            let activity = Self.activity(for: tool)
            if let index = running.firstIndex(where: { $0.id == tool.id }) {
                running[index] = activity
            } else {
                running.append(activity)
            }

        case .permissionRequested(let request):
            guard let index = running.firstIndex(where: { $0.id == request.toolUseID }) else { break }
            beforeWaiting[request.toolUseID] = running[index]
            running[index].kind = .waiting
            running[index].label = "J'attends ton accord"
            running[index].detail = Self.preview(request.summary, last: false)

        case .toolFinished(let id, let failed, let output):
            guard let index = running.firstIndex(where: { $0.id == id }) else { break }
            var activity = beforeWaiting.removeValue(forKey: id) ?? running[index]
            running.remove(at: index)
            activity.succeeded = !failed && !refused.contains(id)
            // A command is worth its last lines; a file keeps the preview of what was written.
            if activity.kind == .running, activity.succeeded || !refused.contains(id) {
                activity.detail = Self.preview(output, last: true)
            }
            live.done.append(activity)
        }
        live.activity = current
    }

    /// The action to show: one that waits for the user first, otherwise the oldest still under way
    /// (tools named in the same message run one after the other).
    private var current: ChatActivity? {
        running.first { $0.kind == .waiting } ?? running.first
    }

    /// The text written so far has gone to the history: the live text starts again from nothing,
    /// so the island does not show it twice.
    mutating func textCommitted() {
        written = ""
        live.text = ""
    }

    /// The user answered a permission request in the island.
    mutating func permissionAnswered(toolUseID: String, allowed: Bool) {
        if !allowed { refused.insert(toolUseID) }
        if allowed, let index = running.firstIndex(where: { $0.id == toolUseID }), let before = beforeWaiting[toolUseID] {
            running[index] = before
        }
        live.activity = current
    }

    // MARK: Wording

    /// What a tool does, in a few French words.
    static func activity(for tool: ChatToolUse) -> ChatActivity {
        let file = (tool.detail as NSString).lastPathComponent
        let short = short(tool.detail)
        func label(_ verb: String, _ object: String, alone: String) -> String {
            object.isEmpty ? alone : "\(verb) \(object)"
        }
        var kind = ChatActivity.Kind.running
        var text: String
        var detail: String?
        switch tool.name {
        case "Read", "NotebookRead":
            kind = .reading
            text = label("Je lis", file, alone: "Je lis un fichier")
        case "Write":
            kind = .writing
            text = label("J'écris", file, alone: "J'écris un fichier")
            detail = preview(tool.content, last: false)
        case "Edit", "MultiEdit", "NotebookEdit":
            kind = .editing
            text = label("Je modifie", file, alone: "Je modifie un fichier")
            detail = preview(tool.content, last: false)
        case "Bash":
            text = label("Je lance", short, alone: "Je lance une commande")
        case "Grep", "Glob", "LS", "ToolSearch":
            kind = .searching
            text = label("Je cherche", short, alone: "Je cherche dans le dossier")
        case "WebSearch":
            kind = .searching
            text = label("Je cherche sur le web :", short, alone: "Je cherche sur le web")
        case "WebFetch":
            kind = .reading
            text = label("Je lis", URL(string: tool.detail)?.host ?? short, alone: "Je lis une page")
        case "Task", "Agent", "TodoWrite":
            kind = .thinking
            text = tool.name == "TodoWrite" ? "Je m'organise" : label("Je délègue :", short, alone: "Je délègue une tâche")
        default:
            text = "J'utilise \(tool.name)"
        }
        return ChatActivity(id: tool.id, kind: kind, label: text, detail: detail)
    }

    private static func short(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return oneLine.count > 40 ? String(oneLine.prefix(39)) + "…" : oneLine
    }

    /// A few lines of a text, each cut to the width: the first ones of a file, the last ones of an output.
    /// nil when there is nothing to show.
    static func preview(_ text: String, last: Bool) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }
        let kept = last ? Array(lines.suffix(previewLines)) : Array(lines.prefix(previewLines))
        return kept.map { $0.count > previewWidth ? String($0.prefix(previewWidth - 1)) + "…" : $0 }
            .joined(separator: "\n")
    }

    /// What the folded island says about the answer in progress.
    static func headline(_ live: ChatLive) -> String {
        if let activity = live.activity { return activity.label }
        return live.text.isEmpty ? "Je réfléchis" : "Je réponds"
    }
}

/// Limits how often something is published: at most once per interval, never losing the last value.
struct PublishThrottle: Sendable {
    let interval: TimeInterval
    private var last: Date?

    init(interval: TimeInterval = 0.1) { self.interval = interval }

    /// Seconds to wait before publishing: 0 means now. Call `published(at:)` when it is done.
    func delay(now: Date) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }

    mutating func published(at now: Date) { last = now }
}
