import Foundation

/// Decides what an answer leaves in the history, in the order it happened: what Yumi wrote, the
/// line of each action, what it wrote next, and so on up to the conclusion. Pure: events in,
/// lines out.
struct ChatTranscript: Sendable {
    /// Text written but not yet in the history: it goes there when an action follows it, or at the end.
    private var pendingText = ""
    private var tools: [String: ChatToolUse] = [:]
    private var refused: Set<String> = []
    /// Everything already given, to avoid saying the conclusion twice.
    private var given: [String] = []

    /// The lines to add to the history after this event.
    mutating func apply(_ event: ChatStreamEvent) -> [String] {
        switch event {
        case .text(let text):
            // Two blocks of text in a row: the first one is complete, keep it.
            let lines = flushText()
            pendingText = text
            return lines

        case .toolStarted(let tool):
            tools[tool.id] = tool
            // What was written before the action comes before its line.
            return flushText()

        case .toolFinished(let id, let failed, _):
            guard let tool = tools.removeValue(forKey: id) else { return [] }
            let outcome: ChatToolOutcome = refused.contains(id) ? .refused : (failed ? .failed : .done)
            return give(ChatPhrases.action(tool, outcome: outcome).map { [$0] } ?? [])

        case .started, .messageStarted, .textDelta, .toolAnnounced, .permissionRequested, .permissionCancelled, .finished:
            return []
        }
    }

    /// The user refused this tool in the island: its line will say so.
    mutating func refuse(toolUseID: String) {
        refused.insert(toolUseID)
    }

    /// The last lines, when the turn ends well: the text still pending, and the conclusion if it
    /// says something more. Empty when the answer had no text at all.
    mutating func finish(_ result: ChatTurnResult) -> [String] {
        var lines = flushText()
        let conclusion = result.text
        // The result repeats the last message: it is only added when it was not already given.
        if !conclusion.isEmpty, !given.contains(where: { $0 == conclusion || $0.hasSuffix(conclusion) }) {
            lines += give([conclusion])
        }
        return lines
    }

    /// True when at least one line of text (not an action) was given.
    private(set) var hasText = false

    private mutating func flushText() -> [String] {
        defer { pendingText = "" }
        guard !pendingText.isEmpty else { return [] }
        hasText = true
        return give([pendingText])
    }

    private mutating func give(_ lines: [String]) -> [String] {
        given += lines
        return lines
    }
}
