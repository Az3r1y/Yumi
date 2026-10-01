import Foundation

// MARK: - Live chat contract
// What the chat is doing right now, so the island can show it as it happens instead of
// after the fact. The core fills `AppState.chatLive` while a message is being answered and
// sets it back to nil when the answer is complete; the island draws it. Both sides rely on
// this file, so neither edits it during the parallel work (see YUMI.md).

/// The answer in progress. nil in `AppState` when the chat is idle.
struct ChatLive: Equatable, Sendable {
    /// The reply written so far. It grows as the words arrive; empty before the first one.
    var text: String = ""
    /// The action under way, or nil while Yumi is only writing or thinking.
    var activity: ChatActivity? = nil
    /// Actions already finished during this answer, oldest first.
    var done: [ChatActivity] = []
}

/// One thing the chat does besides writing: reading a file, creating one, running a command.
struct ChatActivity: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case thinking, reading, writing, editing, running, searching, waiting
    }
    let id: String
    var kind: Kind
    /// A few words in French: "Écrit bonjour.txt", "Lance swift test", "Lit Budget.pdf".
    var label: String
    /// What can be shown underneath when there is room: the content being written, the
    /// last lines a command printed. A few lines at most, already cut by the core.
    var detail: String? = nil
    /// false when the action failed or was refused.
    var succeeded: Bool = true
}
