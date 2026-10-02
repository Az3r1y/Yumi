import Foundation

// MARK: - Initiative contract
// Yumi speaks first, rarely and to the point (see design/yumi/voix.md). The core decides
// when and what: it sets `AppState.remark`. The island shows it next to Yumi, lets the
// person answer or wave it away, and reports back through the notifications below.
// Both sides rely on this file, so neither edits it during the parallel work.

/// One thing Yumi says on his own. nil in `AppState` when he has nothing to say.
struct YumiRemark: Identifiable, Equatable, Sendable {
    let id: String
    /// One or two short sentences, in Yumi's voice.
    var text: String
    /// The face he makes while saying it.
    var mood: YumiMood = .neutral
    /// A short label for the one thing the person can do about it: "Pause", "Voir". nil for none.
    var action: String? = nil
    /// Seconds the remark stays if nobody touches it.
    var duration: Double = 8
}

/// How much Yumi speaks on his own. Stored by the island under `YumiTalk.defaultsKey`.
enum YumiTalk: String, CaseIterable, Sendable {
    /// Never speaks first.
    case silent
    /// Only what matters: a few times a day at most. The default.
    case discreet
    /// Also small talk: greetings, encouragements.
    case chatty

    static let defaultsKey = "yumiTalk"
}

extension Notification.Name {
    /// Posted by the island when the person presses the remark's action. userInfo: ["id": String]
    static let remarkAccepted = AppIdentity.notification("remarkAccepted")
    /// Posted by the island when the remark is closed or times out. userInfo: ["id": String, "ignored": Bool]
    static let remarkDismissed = AppIdentity.notification("remarkDismissed")
}
