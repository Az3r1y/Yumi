import Foundation

/// What the permission system tells the rest of Yumi. It describes; it never moves the
/// character or opens a view. The island and the character decide how Yumi reacts.
enum PermissionEvent: Equatable, Sendable {
    /// Yumi needs the person's consent: the approval is about to be shown.
    case permissionRequired(ApprovalRequest)
    /// The approval is on screen; nothing goes on without the person.
    case waitingForUser(approvalID: UUID)
    case approved(approvalID: UUID, scope: PermissionScope)
    case denied(approvalID: UUID)
    case expired(approvalID: UUID)
    case cancelled(approvalID: UUID)
}

/// The person's answer to an approval. Only the view that showed it can give one, through
/// the closure it received with the approval: there is no other way to answer.
enum ApprovalAnswer: Equatable, Sendable {
    /// Allow, with this scope. A scope the approval did not offer counts as `.oneTime`.
    case approve(PermissionScope)
    case deny

    static let approveOnce = ApprovalAnswer.approve(.oneTime)
    static let approveForSession = ApprovalAnswer.approve(.session)
}

/// Shows approvals to the person: the island's approval queue in the app, a script in the tests.
@MainActor
protocol ApprovalPresenter: AnyObject {
    /// Shows the approval. `answer` is called at most once, from a click of the person.
    /// `shown` is called when the approval is really on screen: it may first wait behind other
    /// requests, and the time to answer only starts then.
    func present(_ approval: ApprovalRequest, shown: @escaping @MainActor () -> Void,
                 answer: @escaping @MainActor (ApprovalAnswer) -> Void)
    /// The approval ended without an answer (expired, cancelled): take it off screen.
    func withdraw(_ approvalID: UUID)
}
