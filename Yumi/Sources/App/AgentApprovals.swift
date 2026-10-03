import Foundation

/// Shows the permission system's approvals in the island's approval queue, the same place as
/// Claude Code's requests, and turns a click into an `ApprovalAnswer`. The only path from the
/// person to a permission.
@MainActor
final class IslandApprovalPresenter: ApprovalPresenter {
    func present(_ approval: ApprovalRequest, answer: @escaping @MainActor (ApprovalAnswer) -> Void) {
        HookServer.shared.presentAgentApproval(approval) { decision in
            switch decision {
            case "allow": answer(.approveOnce)
            case "always": answer(.approveForSession)
            case "deny": answer(.deny)
            // No answer in time is the permission system's to decide (it expires the request).
            default: break
            }
        }
    }

    func withdraw(_ approvalID: UUID) {
        HookServer.shared.withdrawAgentApproval(id: approvalID)
    }
}

/// How Yumi reacts to the permission system, with the character's existing vocabulary. The
/// permission system only describes; this is where it becomes a look, a pose or a state.
enum ApprovalReaction {
    @MainActor
    static func apply(_ event: PermissionEvent, to state: AppState) {
        switch event {
        case .permissionRequired:
            // Yumi turns to the person before the question shows.
            NotificationCenter.default.post(name: .yumiGaze, object: CGPoint(x: 0, y: 0.6))
        case .waitingForUser:
            break // The approval view sets the waiting state (HookServer.showApproval).
        case .approved:
            NotificationCenter.default.post(name: .yumiGaze, object: nil)
            NotificationCenter.default.post(name: .yumiPose, object: YumiPose.pop)
            state.stateOverride = .working
        case .denied:
            NotificationCenter.default.post(name: .yumiGaze, object: nil)
            if state.stateOverride == .approval || state.stateOverride == .working { state.stateOverride = nil }
        case .expired, .cancelled:
            NotificationCenter.default.post(name: .yumiGaze, object: nil)
            if state.stateOverride == .approval { state.stateOverride = nil }
        }
    }
}
