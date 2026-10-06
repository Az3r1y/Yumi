import Foundation

/// One rule the person configured: for this tool (and kind of action), on this target, decide
/// allow, ask or deny. Rules come from the settings only: no tool, plan, model or content can
/// write one.
struct PolicyRule: Identifiable, Equatable, Codable, Sendable {
    enum Effect: String, Codable, Sendable { case allow, ask, deny }

    enum Target: Equatable, Codable, Sendable {
        /// Inside this project folder.
        case project(String)
        /// Exactly this resource.
        case resource(ResourceRef)
        /// This account or this site (`https://example.com`).
        case account(String)
        /// Anywhere. Only for `ask` and `deny`: nothing is ever allowed everywhere.
        case anywhere
    }

    let id: UUID
    /// A tool id, or `*` for every tool (deny and ask only).
    var toolID: String
    /// nil: every kind of action of the tool.
    var kind: ActionKind?
    var target: Target
    var effect: Effect

    init(id: UUID = UUID(), toolID: String, kind: ActionKind? = nil, target: Target, effect: Effect) {
        self.id = id
        self.toolID = toolID
        self.kind = kind
        self.target = target
        self.effect = effect
    }

    /// A rule that allows must name one tool and a bounded target. Anything broader is refused
    /// when the rule is added, and ignored if it was written to disk by hand.
    var isValid: Bool {
        guard toolID == "*" || ToolRegistry.isValidIdentifier(toolID) else { return false }
        guard effect == .allow else { return true }
        if toolID == "*" { return false }
        switch target {
        case .anywhere: return false
        case .project(let path): return path.hasPrefix("/") && path != "/" && path != NSHomeDirectory()
        case .resource(let resource): return resource.kind != .unknown
        case .account(let name): return !name.isEmpty
        }
    }

    func matches(_ request: AgentPermissionRequest, _ assessment: ActionAssessment) -> Bool {
        guard toolID == "*" || toolID == request.toolID else { return false }
        if let kind, kind != assessment.kind { return false }
        switch target {
        case .anywhere:
            return true
        case .project(let root):
            // Every resource must be a file inside the project: one outside, and the rule does not apply.
            return assessment.isScoped && assessment.resources.allSatisfy {
                $0.kind == .file && RiskAssessor.path($0.identifier, isInside: root)
            }
        case .resource(let resource):
            return assessment.isScoped && assessment.resources.allSatisfy { $0 == resource }
        case .account(let name):
            return assessment.isScoped && assessment.container == name.lowercased()
        }
    }
}

/// The verdict of the configured rules, before what the person allowed earlier.
enum PolicyVerdict: Equatable, Sendable {
    case allow, ask
    case deny(String)
}

/// The rules the person configured. Decides only what a rule says; what no rule covers is left
/// to the defaults of `LocalPermissionManager` (and the risk of each action to `RiskAssessor`).
struct PermissionPolicy: Equatable, Codable, Sendable {
    var rules: [PolicyRule] = []

    /// Deny wins over ask, ask over allow. An allow never reaches above medium: for a high risk
    /// it becomes an ask, for a critical one nothing (the default refusal stands).
    func verdict(for request: AgentPermissionRequest, _ assessment: ActionAssessment) -> PolicyVerdict? {
        let matching = rules.filter { $0.isValid && $0.matches(request, assessment) }
        if matching.contains(where: { $0.effect == .deny }) { return .deny(loc("Une règle de tes réglages l'interdit.")) }
        if matching.contains(where: { $0.effect == .ask }) { return .ask }
        if matching.contains(where: { $0.effect == .allow }) {
            switch assessment.risk {
            case .safe, .low, .medium: return .allow
            case .high: return .ask
            case .critical: return nil
            }
        }
        return nil
    }
}
