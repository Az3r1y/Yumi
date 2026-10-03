import Foundation

/// Something the person allowed (or a policy they configured). Built only by
/// `LocalPermissionManager` from an answer of the person, or by the settings.
struct Permission: Identifiable, Equatable, Codable, Sendable {
    enum Origin: String, Codable, Sendable {
        /// A click of the person on an approval.
        case user
        /// Written by the person in the settings.
        case settings
    }

    let id: UUID
    var scope: PermissionScope
    var toolID: String
    /// nil only for `.tool`.
    var kind: ActionKind?
    /// The highest risk it covers. Never above medium for anything but `.oneTime`.
    var maxRisk: RiskLevel
    /// The project folder or account it is bounded to.
    var container: String?
    /// The exact resources, for `.resource` and `.session` without a container.
    var resources: [ResourceRef]
    /// For `.oneTime`: the run and the exact actions (`AgentPermissionRequest.fingerprint`) it covers.
    var runID: UUID?
    var actions: [String]
    var origin: Origin
    var createdAt: Date
    /// Session permissions also end after a while, even if Yumi keeps running.
    var expiresAt: Date?

    /// True when this permission covers that request, assessed.
    func covers(_ request: AgentPermissionRequest, _ assessment: ActionAssessment, now: Date) -> Bool {
        if let expiresAt, now >= expiresAt { return false }
        guard request.toolID == toolID, assessment.risk <= maxRisk else { return false }
        switch scope {
        case .oneTime:
            return request.runID == runID && actions.contains(request.fingerprint)
        case .tool:
            guard assessment.isScoped, let container, assessment.container == container else { return false }
            return assessment.risk <= .medium
        case .session, .project, .resource:
            guard assessment.kind == kind, assessment.isScoped, assessment.risk <= .medium else { return false }
            if let container, scope != .resource {
                return assessment.container == container
            }
            return Set(assessment.resources).isSubset(of: Set(resources))
        }
    }
}
