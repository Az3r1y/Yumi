import Foundation

// MARK: - Event animation contract
// Things that happen in the outside world and deserve a small scene of their own: a star
// on a repository, a fork, a merged pull request. A module posts `yumiScene`; the character
// plays the matching scene once, then returns to what he was doing. The island does not
// take part. Both sides rely on this file, so neither edits it during the parallel work.

/// A scene Yumi plays once for an outside event.
enum YumiScene: String, CaseIterable, Sendable {
    /// Someone starred a repository: a star falls, he catches it, his eyes sparkle.
    case star
    /// Someone forked a repository: he splits in two, the copy waves and leaves.
    case fork
    /// A pull request was opened: he holds up a small branch.
    case pullRequest
    /// A pull request was merged: a second drop joins him and they become one.
    case merge
    /// Commits were pushed: he throws a drop upward, it flies off.
    case push
    /// A commit was made locally: a dot adds itself to a little line beside him.
    case commit
    /// An issue was opened: a mark pops above his head, he looks at it.
    case issue
    /// A release was published: confetti, he bows.
    case release
    /// A new follower: a small slime peeks in from the side and waves.
    case follower
}

extension Notification.Name {
    /// object: `YumiScene`. userInfo, optional: ["count": Int] when several happened at once.
    static let yumiScene = AppIdentity.notification("yumiScene")
}
