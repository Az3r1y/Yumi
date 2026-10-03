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

/// How Yumi reacts to the agent runtime: each activity gets the island state, mood and pose of
/// `AgentLook`, and the end of a run what he says about it. The runtime only describes.
@MainActor
final class AgentReaction {
    private weak var state: AppState?
    private var lastActivity: AgentActivity = .idle
    private var clearing: Task<Void, Never>?
    private var dismissal: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        // The island closes a remark itself: one of ours is then gone.
        dismissal = NotificationCenter.default.addObserver(forName: .remarkDismissed, object: nil, queue: .main) { [weak self] note in
            let id = note.userInfo?["id"] as? String
            MainActor.assumeIsolated {
                guard let id, id.hasPrefix("agent-"), self?.state?.remark?.id == id else { return }
                self?.state?.remark = nil
            }
        }
    }

    func apply(_ event: AgentEvent, agent: RuntimeAgent) {
        guard let state else { return }
        let activity = agent.activity
        if activity != lastActivity {
            lastActivity = activity
            show(activity, in: state)
        }
        switch event.kind {
        case .agentCompleted, .agentFailed, .agentCancelled:
            // Asked from the chat, the answer is written there (ClaudeService.runAsAgent).
            guard state.view != .prompt, let result = agent.current?.result, let remark = AgentLook.remark(for: result) else { return }
            say(remark, in: state)
        default:
            break
        }
    }

    private func show(_ activity: AgentActivity, in state: AppState) {
        let look = AgentLook.of(activity)
        clearing?.cancel()
        let center = NotificationCenter.default
        center.post(name: .yumiMood, object: activity == .idle ? nil : look.mood)
        if let pose = look.pose { center.post(name: .yumiPose, object: pose) }
        let agentStates: Set<BotState> = [.thinking, .working, .searching, .approval, .finished, .error]
        switch activity {
        case .planning, .thinking: state.stateOverride = .thinking
        case .waiting: break // The approval view sets it (HookServer.showApproval).
        case .working: state.stateOverride = .working
        case .checking: state.stateOverride = .searching
        case .success, .error:
            state.stateOverride = activity == .success ? .finished : .error
            // The verdict stays a moment, then Yumi goes back to what he was doing.
            let shown = state.stateOverride
            clearing = Task { [weak state] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, let state, state.stateOverride == shown else { return }
                state.stateOverride = nil
                NotificationCenter.default.post(name: .yumiMood, object: nil)
            }
        case .idle:
            if let current = state.stateOverride, agentStates.contains(current) { state.stateOverride = nil }
        }
    }

    private func say(_ remark: YumiRemark, in state: AppState) {
        state.remark = remark
        Task { [weak state] in
            try? await Task.sleep(for: .seconds(remark.duration))
            guard let state, state.remark?.id == remark.id else { return }
            state.remark = nil
        }
    }
}
