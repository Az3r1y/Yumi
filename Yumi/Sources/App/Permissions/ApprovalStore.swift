import Foundation

/// The approvals waiting for the person, and how each one ended. An approval ends once: the
/// first of answer, expiry or cancellation wins, and an answer to an approval that already
/// ended (or that never existed) changes nothing. In memory only.
@MainActor
final class ApprovalStore {
    private var pending: [UUID: ApprovalRequest] = [:]
    private var order: [UUID] = []
    private var waiters: [UUID: [CheckedContinuation<ApprovalRequest.Status, Never>]] = [:]
    /// How recent approvals ended, so a late answer is recognised and refused.
    private var ended: [UUID: ApprovalRequest.Status] = [:]
    private var endedOrder: [UUID] = []

    /// The approvals waiting, oldest first.
    var waiting: [ApprovalRequest] { order.compactMap { pending[$0] } }

    func add(_ approval: ApprovalRequest) {
        guard pending[approval.id] == nil, ended[approval.id] == nil else { return }
        pending[approval.id] = approval
        order.append(approval.id)
    }

    func approval(id: UUID) -> ApprovalRequest? { pending[id] }

    /// Moves the deadline of an approval still waiting.
    func setExpiry(_ id: UUID, to date: Date) { pending[id]?.expiresAt = date }

    func status(of id: UUID) -> ApprovalRequest.Status? { pending[id]?.status ?? ended[id] }

    /// Ends an approval. Returns it with its final status, or nil when it was not pending.
    @discardableResult
    func resolve(_ id: UUID, as status: ApprovalRequest.Status) -> ApprovalRequest? {
        guard status.isFinal, var approval = pending.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        approval.status = status
        ended[id] = status
        endedOrder.append(id)
        if endedOrder.count > 500 { ended[endedOrder.removeFirst()] = nil }
        for waiter in waiters.removeValue(forKey: id) ?? [] { waiter.resume(returning: status) }
        return approval
    }

    /// Waits until the approval ends. Returns at once when it already has.
    func wait(for id: UUID) async -> ApprovalRequest.Status {
        if let status = ended[id] { return status }
        guard pending[id] != nil else { return .cancelled }
        return await withCheckedContinuation { waiters[id, default: []].append($0) }
    }

    func waiting(for runID: UUID) -> [ApprovalRequest] { waiting.filter { $0.agentRunID == runID } }
}
