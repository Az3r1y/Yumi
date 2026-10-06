import Foundation

/// What Yumi asks the person, for one action or several similar ones of the same run. Every
/// word of the headline, the resources, the risk and the consequences is built by the
/// permission system from the tool's code; only `goal` and `reason` come from the planner,
/// and they are shown as such, never trusted.
struct ApprovalRequest: Identifiable, Equatable, Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending, approved, denied, expired, cancelled

        var isFinal: Bool { self != .pending }
    }

    /// One step this approval covers.
    struct Item: Equatable, Codable, Sendable {
        var stepID: String
        /// `AgentPermissionRequest.fingerprint`: the tool and its exact arguments.
        var fingerprint: String
        var resources: [ResourceRef]
    }

    /// Random, never shown to a planner or a model: an answer is matched by it.
    let id: UUID
    var agentRunID: UUID
    var toolID: String
    var toolName: String
    var action: ActionKind?
    /// What the plan wants to achieve, as the planner wrote it.
    var goal: String
    /// Why this step, as the planner wrote it.
    var reason: String
    var riskLevel: RiskLevel
    /// What "Autoriser" gives: always `.oneTime`.
    var scope: PermissionScope = .oneTime
    /// What the person may choose instead (`.session` when the risk and the resources allow it).
    var offeredScopes: [PermissionScope] = [.oneTime]
    var resources: [ResourceRef]
    /// The project folder or the account, when all resources share one.
    var container: String?
    var reversible: Bool
    /// What the action writes, from the tool (`ToolAction.content`): shown in full before agreeing.
    var content: String?
    var items: [Item]
    let createdAt: Date
    var expiresAt: Date
    var status: Status = .pending

    init(id: UUID = UUID(), agentRunID: UUID, toolID: String, toolName: String, action: ActionKind?,
         goal: String, reason: String, riskLevel: RiskLevel, offeredScopes: [PermissionScope] = [.oneTime],
         resources: [ResourceRef], container: String?, reversible: Bool, content: String? = nil, items: [Item],
         createdAt: Date, expiresAt: Date) {
        self.content = content
        self.id = id
        self.agentRunID = agentRunID
        self.toolID = toolID
        self.toolName = toolName
        self.action = action
        self.goal = goal
        self.reason = reason
        self.riskLevel = riskLevel
        self.offeredScopes = offeredScopes
        self.resources = resources
        self.container = container
        self.reversible = reversible
        self.items = items
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    var offersSession: Bool { offeredScopes.contains(.session) }

    // MARK: - What the person reads

    /// One sentence, in Yumi's voice: "Je dois modifier 2 fichiers dans le projet Yumi."
    var headline: String {
        let verb = switch action {
        case .read: "lire"
        case .create: loc("créer")
        case .modify: "modifier"
        case .delete: "supprimer"
        case .run: "lancer"
        case .send: "envoyer"
        case .publish: "publier"
        case .pay: "payer"
        case .other, nil: "utiliser"
        }
        let object: String
        if resources.count == 1 {
            object = resources[0].kind == .command ? "une commande" : Self.displayName(resources[0], in: container)
        } else if resources.isEmpty {
            object = action == nil || action == .other ? toolName : loc("quelque chose avec \(toolName)")
        } else {
            let files = resources.allSatisfy { $0.kind == .file }
            object = "\(resources.count) \(files ? "fichiers" : "éléments")"
        }
        return loc("Je dois \(verb) \(object)\(place).")
    }

    /// What will be touched, on one line, when there is a single thing to show: the command, a
    /// text of one line. A text of several lines is shown by `contentPreview` instead.
    var subject: String? {
        if let content {
            let lines = Self.lines(of: content)
            if lines.count <= 1 { return "« \(lines.first ?? "") »" }
            return nil
        }
        guard resources.count == 1 else { return nil }
        let resource = resources[0]
        return resource.kind == .command ? resource.identifier : nil
    }

    /// Lines of a text of several lines, as the person reads them before agreeing: the first
    /// ones, then how many more. nil for a text of one line (`subject` shows it).
    var contentPreview: [String]? {
        guard let content else { return nil }
        let lines = Self.lines(of: content)
        guard lines.count > 1 else { return nil }
        var shown = lines.prefix(Self.previewLines).map { $0.isEmpty ? " " : $0 }
        if lines.count > Self.previewLines {
            let more = lines.count - Self.previewLines
            shown.append(loc("… et \(more) ligne\(more > 1 ? "s" : "") de plus"))
        }
        return shown
    }

    static let previewLines = 5

    /// The lines of a text, without the empty ones at its end.
    static func lines(of text: String) -> [String] {
        var lines = text.components(separatedBy: .newlines)
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }

    /// The planner's goal, cut to one short line.
    var intro: String? { Self.oneLine(goal, limit: 80) }

    /// "Voir les détails": tool, resources, scope, risk, reason, consequences.
    var details: [String] {
        var lines = ["Outil : \(toolName)"]
        if !resources.isEmpty {
            let names = resources.prefix(6).map { Self.displayName($0, in: container) }
            lines.append("Concerne : " + names.joined(separator: ", ") + (resources.count > 6 ? " et \(resources.count - 6) autres" : ""))
        }
        if let content {
            let count = Self.lines(of: content).count
            let label = action == .create ? loc("Contenu") : loc("Texte ajouté")
            lines.append(count > 1 ? "\(label) : \(count) lignes, \(content.count) caractères" : "\(label) : « \(content.trimmingCharacters(in: .newlines)) »")
        }
        lines.append(loc("Portée : \(scope.label)") + (offersSession ? loc(" (ou cette session)") : ""))
        lines.append("Risque : \(riskLevel.label)")
        if let why = Self.oneLine(reason, limit: 120) { lines.append(loc("Raison donnée par l'agent : \(why)")) }
        lines.append(reversible ? loc("Conséquence : réversible") : loc("Conséquence : on ne pourra pas revenir en arrière"))
        return lines
    }

    private var place: String {
        guard let container else { return "" }
        if resources.contains(where: { $0.kind == .file }) {
            return loc(" dans le projet \((container as NSString).lastPathComponent)")
        }
        if resources.count == 1, resources[0].identifier == container { return "" }
        return " sur \(container)"
    }

    /// A file relative to its project, a site by its host, anything else as it is.
    /// A file outside a project shows its whole place, from the home folder: `~/Downloads/todo.md`.
    static func displayName(_ resource: ResourceRef, in container: String?, home: String = NSHomeDirectory()) -> String {
        switch resource.kind {
        case .file:
            if let container, RiskAssessor.path(resource.identifier, isInside: container), resource.identifier != container {
                return String(resource.identifier.dropFirst(container.count + 1))
            }
            if RiskAssessor.path(resource.identifier, isInside: home), resource.identifier != home {
                return "~" + resource.identifier.dropFirst(home.count)
            }
            return resource.identifier
        case .url:
            return URL(string: resource.identifier)?.host ?? resource.identifier
        case .command, .account, .yumi, .unknown:
            return resource.identifier
        }
    }

    static func oneLine(_ text: String, limit: Int) -> String? {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}
