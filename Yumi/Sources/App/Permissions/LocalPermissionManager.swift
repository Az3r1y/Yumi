import Foundation
import Observation

/// Yumi's permission system: the `PermissionManager` the agent runtime asks about every step.
///
/// For each request: the tool's own description of the action is checked and assessed
/// (`RiskAssessor`), then decided in this order, the first answer wins:
///
/// 1. a rule of the settings that denies → deny;
/// 2. critical → deny, or ask if a rule says to ask; never allowed;
/// 3. approved by the person for this very action of this run → allow;
/// 4. high → ask, always;
/// 5. a rule that asks → ask; a rule that allows → allow;
/// 6. something the person allowed before, for this tool, action and scope → allow;
/// 7. the defaults: safe → allow; low → allow for what the person chose themselves or inside a
///    project they already allowed this session, ask otherwise; medium → ask.
///
/// Similar steps of the same run (same tool, action, risk and project) are asked together.
/// Permissions only come from the person (an answer to an approval, through the closure given
/// to the presenter) or from the settings. Nothing the runtime passes in, and nothing a tool,
/// a plan, a model or a page says, can add one.
@MainActor
@Observable
final class LocalPermissionManager: PermissionManager {
    private(set) var policy: PermissionPolicy
    @ObservationIgnored private let assessor: RiskAssessor
    @ObservationIgnored private let store: any PermissionStore
    @ObservationIgnored let audit: PermissionAuditLog
    @ObservationIgnored private let approvals = ApprovalStore()
    @ObservationIgnored weak var presenter: (any ApprovalPresenter)?
    /// How long an approval waits for the person.
    @ObservationIgnored let approvalLifetime: Duration
    /// A session permission also ends after this long.
    @ObservationIgnored let sessionLifetime: TimeInterval
    @ObservationIgnored private let clock: @Sendable () -> Date

    /// `.session` and `.tool`: until Yumi quits.
    private(set) var sessionPermissions: [Permission] = []
    /// `.project` and `.resource`: saved.
    private(set) var rememberedPermissions: [Permission] = []
    /// `.oneTime`: for the steps of a run approved together, each usable once.
    @ObservationIgnored private var runPermissions: [Permission] = []
    /// Files the person handed to Yumi themselves, this session.
    @ObservationIgnored private var chosenByPerson: Set<String> = []
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<PermissionEvent>.Continuation] = [:]

    init(store: any PermissionStore = MemoryPermissionStore(),
         audit: PermissionAuditLog = PermissionAuditLog(sink: MemoryAuditSink()),
         assessor: RiskAssessor = RiskAssessor(),
         approvalLifetime: Duration = .seconds(60),
         sessionLifetime: TimeInterval = 12 * 3600,
         clock: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.audit = audit
        self.approvalLifetime = approvalLifetime
        self.sessionLifetime = sessionLifetime
        self.clock = clock
        let record = store.load()
        // What is read back is checked again: a file edited by hand cannot widen anything.
        policy = PermissionPolicy(rules: record.rules.filter(\.isValid))
        self.assessor = assessor
        rememberedPermissions = record.permissions.filter(Self.isValidRemembered)
    }

    // MARK: - PermissionManager

    func evaluate(_ request: AgentPermissionRequest, upcoming: [AgentPermissionRequest]) async -> PermissionEvaluation {
        let now = clock()
        let assessment: ActionAssessment
        switch assessor.assess(request) {
        case .failure(.invalidResource):
            record(request, nil, .blocked, by: .system, scope: nil)
            return .deny(reason: "Je ne sais pas exactement ce que cette action toucherait.")
        case .success(let value):
            assessment = value
        }

        switch verdict(request, assessment, now: now) {
        case .allow(let source, let permission):
            if let permission, permission.scope == .oneTime { consume(permission, for: request) }
            record(request, assessment, .allowed, by: source, scope: permission?.scope)
            return .allow
        case .deny(let reason, let source):
            record(request, assessment, .blocked, by: source, scope: nil)
            return .deny(reason: reason)
        case .ask:
            guard let presenter else {
                record(request, assessment, .blocked, by: .system, scope: nil)
                return .deny(reason: "Je ne peux pas te demander ton accord maintenant.")
            }
            let approval = makeApproval(for: request, assessment, upcoming: upcoming, now: now)
            approvals.add(approval)
            emit(.permissionRequired(approval))
            let id = approval.id
            presenter.present(approval) { [weak self] answer in self?.answer(id, answer) }
            emit(.waitingForUser(approvalID: id))
            let lifetime = approvalLifetime
            Task { [weak self] in
                try? await Task.sleep(for: lifetime)
                self?.end(id, as: .expired)
            }
            return .ask(approval)
        }
    }

    func decision(on approval: ApprovalRequest) async -> PermissionDecision {
        let id = approval.id
        let status = await withTaskCancellationHandler {
            await approvals.wait(for: id)
        } onCancel: {
            Task { @MainActor [weak self] in self?.end(id, as: .cancelled) }
        }
        switch status {
        case .approved: return .granted
        case .denied: return .denied(reason: "Tu as refusé.")
        case .expired: return .expired
        case .cancelled, .pending: return .cancelled
        }
    }

    func finishRun(_ runID: UUID) async {
        for approval in approvals.waiting(for: runID) { end(approval.id, as: .cancelled) }
        runPermissions.removeAll { $0.runID == runID }
    }

    // MARK: - The person and the settings

    /// The approvals waiting for an answer, oldest first.
    var waitingApprovals: [ApprovalRequest] { approvals.waiting }

    /// Every event from now on.
    func events() -> AsyncStream<PermissionEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: PermissionEvent.self, bufferingPolicy: .bufferingNewest(64))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// A file the person handed to Yumi (dropped, chosen in a panel). Reading it needs no
    /// question for the rest of the session. Only the views call this, never a tool.
    func personChose(file path: String) {
        guard case .success(let assessment) = assessor.assess(AgentPermissionRequest(
            runID: UUID(), stepID: "", goal: "", reason: "", toolID: "choice", toolName: "", risk: .read, arguments: [:],
            action: ToolAction(kind: .read, resources: [.file(path)]), requiresApproval: false)) else { return }
        chosenByPerson.formUnion(assessment.resources.map(\.identifier))
    }

    /// Adds a rule from the settings. Refused when it would allow too much.
    @discardableResult
    func addRule(_ rule: PolicyRule) -> Bool {
        var rule = rule
        // Only an absolute path is resolved: a relative one would be relative to wherever Yumi runs.
        if case .project(let path) = rule.target, path.hasPrefix("/") {
            rule.target = .project(URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path)
        }
        guard rule.isValid else { return false }
        policy.rules.append(rule)
        save()
        return true
    }

    func removeRule(_ id: UUID) {
        policy.rules.removeAll { $0.id == id }
        save()
    }

    /// Takes back a session or remembered permission.
    func revoke(_ id: UUID) {
        sessionPermissions.removeAll { $0.id == id }
        rememberedPermissions.removeAll { $0.id == id }
        save()
    }

    /// Forgets what was allowed for the session (Yumi quitting does the same).
    func endSession() {
        sessionPermissions = []
        chosenByPerson = []
    }

    // MARK: - Deciding

    private enum Verdict {
        case allow(PermissionAuditEntry.DecidedBy, Permission?)
        case ask
        case deny(String, PermissionAuditEntry.DecidedBy)
    }

    private func verdict(_ request: AgentPermissionRequest, _ assessment: ActionAssessment, now: Date) -> Verdict {
        let rule = policy.verdict(for: request, assessment)
        if case .deny(let reason) = rule { return .deny(reason, .rule) }
        if assessment.risk == .critical {
            return rule == .ask ? .ask : .deny("C'est trop risqué : je ne le fais pas.", .defaults)
        }
        if let permission = runPermissions.first(where: { $0.covers(request, assessment, now: now) }) {
            return .allow(.permission, permission)
        }
        if assessment.risk == .high { return .ask }
        if rule == .ask { return .ask }
        if rule == .allow { return .allow(.rule, nil) }
        if let permission = (sessionPermissions + rememberedPermissions).first(where: { $0.covers(request, assessment, now: now) }) {
            return .allow(.permission, permission)
        }
        switch assessment.risk {
        case .safe:
            return .allow(.defaults, nil)
        case .low:
            let files = assessment.resources.filter { $0.kind == .file }.map(\.identifier)
            if assessment.isScoped, assessment.resources.allSatisfy({ $0.kind == .file }),
               files.allSatisfy(chosenByPerson.contains) {
                return .allow(.defaults, nil)
            }
            if assessment.isScoped, let container = assessment.container, isTrusted(container, now: now) {
                return .allow(.permission, nil)
            }
            return .ask
        case .medium, .high, .critical:
            return .ask
        }
    }

    /// A project or account where the person already allowed something this session: reading
    /// in it needs no question.
    private func isTrusted(_ container: String, now: Date) -> Bool {
        (sessionPermissions + rememberedPermissions).contains {
            $0.container == container && ($0.expiresAt.map { now < $0 } ?? true)
        }
    }

    // MARK: - Asking

    private func makeApproval(for request: AgentPermissionRequest, _ assessment: ActionAssessment,
                              upcoming: [AgentPermissionRequest], now: Date) -> ApprovalRequest {
        var items = [ApprovalRequest.Item(stepID: request.stepID, fingerprint: request.fingerprint, resources: assessment.resources)]
        var resources = assessment.resources
        var reversible = assessment.reversible
        // Similar steps of the same run are asked together: same tool, action, risk and project,
        // and each one would have to be asked anyway. Never for a critical risk.
        if assessment.risk != .critical {
            for next in upcoming where next.runID == request.runID && next.toolID == request.toolID
                && next.stepID != request.stepID && !items.contains(where: { $0.fingerprint == next.fingerprint }) {
                guard case .success(let other) = assessor.assess(next), other.kind == assessment.kind,
                      other.risk == assessment.risk, other.container == assessment.container,
                      other.isScoped == assessment.isScoped, case .ask = verdict(next, other, now: now) else { continue }
                items.append(ApprovalRequest.Item(stepID: next.stepID, fingerprint: next.fingerprint, resources: other.resources))
                for resource in other.resources where !resources.contains(resource) { resources.append(resource) }
                reversible = reversible && other.reversible
            }
        }
        var offered: [PermissionScope] = [.oneTime]
        if assessment.risk <= .medium, assessment.isScoped {
            offered.append(.resource)
            if assessment.container != nil {
                offered += [.session, .tool]
                if resources.allSatisfy({ $0.kind == .file }) { offered.append(.project) }
            } else {
                offered.append(.session)
            }
        }
        let expiresAt = now.addingTimeInterval(Double(approvalLifetime.components.seconds)
                                               + Double(approvalLifetime.components.attoseconds) / 1e18)
        return ApprovalRequest(agentRunID: request.runID, toolID: request.toolID, toolName: request.toolName,
                               action: assessment.kind, goal: request.goal, reason: request.reason,
                               riskLevel: assessment.risk, offeredScopes: offered, resources: resources,
                               container: assessment.container, reversible: reversible, items: items,
                               createdAt: now, expiresAt: expiresAt)
    }

    /// The person answered. Called only through the closure given to the presenter.
    private func answer(_ id: UUID, _ answer: ApprovalAnswer) {
        guard let approval = approvals.approval(id: id) else { return }
        let now = clock()
        guard now < approval.expiresAt else {
            end(id, as: .expired)
            return
        }
        switch answer {
        case .deny:
            end(id, as: .denied)
        case .approve(let asked):
            let scope = approval.offeredScopes.contains(asked) ? asked : .oneTime
            guard let approved = approvals.resolve(id, as: .approved) else { return }
            grant(approved, scope: scope, now: now)
            for item in approved.items {
                recordItem(approved, item, .approved, by: .user, scope: scope)
            }
            emit(.approved(approvalID: id, scope: scope))
        }
    }

    /// Ends an approval that is still waiting. Does nothing once it ended.
    private func end(_ id: UUID, as status: ApprovalRequest.Status) {
        guard status != .approved, let ended = approvals.resolve(id, as: status) else { return }
        let decision: PermissionAuditEntry.Decision = switch status {
        case .denied: .denied
        case .expired: .expired
        default: .cancelled
        }
        for item in ended.items {
            recordItem(ended, item, decision, by: status == .denied ? .user : .system, scope: nil)
        }
        presenter?.withdraw(id)
        switch status {
        case .denied: emit(.denied(approvalID: id))
        case .expired: emit(.expired(approvalID: id))
        default: emit(.cancelled(approvalID: id))
        }
    }

    private func grant(_ approval: ApprovalRequest, scope: PermissionScope, now: Date) {
        // The step being asked runs on this answer; the others of the group each once, in this run.
        let others = approval.items.dropFirst().map(\.fingerprint)
        if !others.isEmpty {
            runPermissions.append(Permission(
                id: UUID(), scope: .oneTime, toolID: approval.toolID, kind: approval.action, maxRisk: approval.riskLevel,
                container: approval.container, resources: approval.resources, runID: approval.agentRunID,
                actions: others, origin: .user, createdAt: now, expiresAt: nil))
        }
        guard scope != .oneTime, approval.riskLevel <= .medium else { return }
        let bounded = scope == .resource || approval.container == nil
        let permission = Permission(
            id: UUID(), scope: scope, toolID: approval.toolID, kind: scope == .tool ? nil : approval.action,
            maxRisk: approval.riskLevel, container: bounded ? nil : approval.container,
            resources: bounded ? approval.resources : [], runID: nil, actions: [], origin: .user, createdAt: now,
            expiresAt: scope.isRemembered ? nil : now.addingTimeInterval(sessionLifetime))
        if scope.isRemembered {
            rememberedPermissions.append(permission)
            save()
        } else {
            sessionPermissions.append(permission)
        }
    }

    /// A one-time permission covers each of its actions once.
    private func consume(_ permission: Permission, for request: AgentPermissionRequest) {
        guard let index = runPermissions.firstIndex(where: { $0.id == permission.id }) else { return }
        runPermissions[index].actions.removeAll { $0 == request.fingerprint }
        if runPermissions[index].actions.isEmpty { runPermissions.remove(at: index) }
    }

    // MARK: - Keeping

    private func save() {
        store.save(PermissionRecord(rules: policy.rules, permissions: rememberedPermissions))
    }

    private static func isValidRemembered(_ permission: Permission) -> Bool {
        guard permission.scope.isRemembered, permission.maxRisk <= .medium,
              ToolRegistry.isValidIdentifier(permission.toolID), permission.kind != nil else { return false }
        switch permission.scope {
        case .project: return permission.container.map { $0.hasPrefix("/") && $0 != "/" } ?? false
        case .resource: return !permission.resources.isEmpty && !permission.resources.contains { $0.kind == .unknown }
        default: return false
        }
    }

    private func record(_ request: AgentPermissionRequest, _ assessment: ActionAssessment?,
                        _ decision: PermissionAuditEntry.Decision, by: PermissionAuditEntry.DecidedBy, scope: PermissionScope?) {
        let resources = assessment?.resources ?? []
        audit.record(PermissionAuditEntry(
            date: clock(), runID: request.runID, stepID: request.stepID, approvalID: nil, toolID: request.toolID,
            action: (assessment?.kind ?? request.action?.kind)?.rawValue,
            resources: resources.map { ApprovalRequest.displayName($0, in: assessment?.container) },
            resourceCount: resources.count, risk: assessment?.risk ?? RiskLevel(request.risk),
            decision: decision, scope: scope, decidedBy: by))
    }

    private func recordItem(_ approval: ApprovalRequest, _ item: ApprovalRequest.Item,
                            _ decision: PermissionAuditEntry.Decision, by: PermissionAuditEntry.DecidedBy, scope: PermissionScope?) {
        audit.record(PermissionAuditEntry(
            date: clock(), runID: approval.agentRunID, stepID: item.stepID, approvalID: approval.id, toolID: approval.toolID,
            action: approval.action?.rawValue,
            resources: item.resources.map { ApprovalRequest.displayName($0, in: approval.container) },
            resourceCount: item.resources.count, risk: approval.riskLevel, decision: decision, scope: scope, decidedBy: by))
    }

    private func emit(_ event: PermissionEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
