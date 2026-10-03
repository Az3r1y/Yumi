import Foundation

/// How much an action can affect the person. Decides how the permission system behaves by
/// default: safe runs silently, low and medium run when allowed before, high always asks,
/// critical is refused unless a policy says to ask.
enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Nothing personal, nothing changed: the time, Yumi's own context.
    case safe
    /// Reads the person's data without changing it: a chosen file, metadata.
    case low
    /// Changes something on this Mac that can be undone: create or edit a file, run a known command.
    case medium
    /// Leaves the Mac or cannot be undone: send, publish, delete, change several files at once.
    case high
    /// Large and irreversible: payments, mass deletion, secrets, system files.
    case critical

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.order < rhs.order }

    /// The risk of a tool that cannot describe its action.
    init(_ toolRisk: ToolRisk) {
        self = switch toolRisk {
        case .none: .safe
        case .read: .low
        case .write: .medium
        case .external: .high
        }
    }

    /// One word for the details of an approval and the history.
    var label: String {
        switch self {
        case .safe: "aucun"
        case .low: "faible"
        case .medium: "moyen"
        case .high: "élevé"
        case .critical: "critique"
        }
    }
}

/// Which risk each kind of action carries, and when an action counts as massive. Configurable,
/// but the floors are fixed in `RiskAssessor`: sending, deleting or paying can never be made
/// to look harmless.
struct RiskTable: Equatable, Codable, Sendable {
    var levels: [ActionKind: RiskLevel]
    /// More resources than this in one action: critical (mass deletion, very wide access).
    var massiveCount: Int
    /// Changing more files than this in one action: at least high.
    var severalFilesCount: Int

    static let standard = RiskTable(
        levels: [.read: .low, .create: .medium, .modify: .medium, .run: .medium,
                 .delete: .high, .send: .high, .publish: .high, .other: .high, .pay: .critical],
        massiveCount: 25,
        severalFilesCount: 1)

    /// What no configuration can go below.
    static let floors: [ActionKind: RiskLevel] = [
        .create: .medium, .modify: .medium, .run: .medium,
        .delete: .high, .send: .high, .publish: .high, .other: .high, .pay: .critical,
    ]

    func level(for kind: ActionKind) -> RiskLevel {
        max(levels[kind] ?? .high, Self.floors[kind] ?? .safe)
    }
}

/// A request as the permission system understands it: its real risk, and what it touches,
/// checked and normalised. Built only from the tool's own description of the action.
struct ActionAssessment: Equatable, Sendable {
    var kind: ActionKind?
    var risk: RiskLevel
    /// Normalised: absolute paths without `..` nor symbolic links, URLs reduced to their origin.
    var resources: [ResourceRef]
    /// The project (a folder with a `.git`) or the account all resources belong to, if they share one.
    var container: String?
    var reversible: Bool
    /// True when every resource is identified: only then can a remembered permission cover it.
    var isScoped: Bool
}

/// Turns what a tool says it will do into an `ActionAssessment`, or a reason to refuse.
struct RiskAssessor: Sendable {
    var table: RiskTable = .standard
    /// The project a path belongs to. Injected by the tests; by default the closest folder that
    /// holds a `.git`.
    var projectRoot: @Sendable (String) -> String? = RiskAssessor.gitRoot
    var home: String = NSHomeDirectory()

    enum Refusal: Error, Equatable { case invalidResource(String) }

    func assess(_ request: AgentPermissionRequest) -> Result<ActionAssessment, Refusal> {
        let toolFloor = RiskLevel(request.risk)
        guard let action = request.action else {
            // The tool cannot say what it does: its risk decides, and nothing remembered covers it.
            return .success(ActionAssessment(kind: nil, risk: max(toolFloor, request.requiresApproval ? .medium : .safe),
                                             resources: [], container: nil, reversible: request.risk < .external, isScoped: false))
        }

        var resources: [ResourceRef] = []
        for resource in action.resources {
            guard let normalised = normalise(resource) else { return .failure(.invalidResource(resource.identifier)) }
            if !resources.contains(normalised) { resources.append(normalised) }
        }

        let onlyYumi = !resources.isEmpty && resources.allSatisfy { $0.kind == .yumi }
        var risk: RiskLevel
        if onlyYumi && action.kind == .read {
            // Yumi reading its own state.
            risk = .safe
        } else {
            risk = table.level(for: action.kind)
            // A tool can describe a call as less risky than the tool, never as less than its kind.
            if action.kind != .read { risk = max(risk, min(toolFloor, .medium)) }
        }
        let files = resources.filter { $0.kind == .file }
        if [.create, .modify].contains(action.kind), files.count > table.severalFilesCount { risk = max(risk, .high) }
        if !action.reversible { risk = max(risk, .high) }
        if resources.contains(where: { $0.kind == .unknown }) || (resources.isEmpty && action.kind != .read) {
            risk = max(risk, .medium)
        }
        if resources.contains(where: { $0.kind == .command }) { risk = max(risk, commandRisk(resources)) }
        if resources.contains(where: isSensitive) { risk = .critical }
        if resources.count > table.massiveCount { risk = .critical }
        if request.requiresApproval { risk = max(risk, .medium) }

        let containers = Set(resources.map(container(of:)))
        let container = containers.count == 1 ? containers.first! : nil
        let scoped = !resources.isEmpty && !resources.contains { $0.kind == .unknown }
        return .success(ActionAssessment(kind: action.kind, risk: risk, resources: resources, container: container,
                                         reversible: action.reversible, isScoped: scoped))
    }

    /// The project of a file, the account itself, the origin of a URL.
    func container(of resource: ResourceRef) -> String? {
        switch resource.kind {
        case .file: projectRoot(resource.identifier)
        case .account: resource.identifier
        case .url: resource.identifier
        case .command, .yumi, .unknown: nil
        }
    }

    /// True when `path` is `root` or inside it. Compares whole folder names: `/a/Yumi` does not
    /// contain `/a/YumiOld`.
    static func path(_ path: String, isInside root: String) -> Bool {
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        return path == base || path.hasPrefix(base + "/")
    }

    // MARK: - Normalising

    private func normalise(_ resource: ResourceRef) -> ResourceRef? {
        let raw = resource.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("\0") else { return nil }
        switch resource.kind {
        case .file:
            let expanded = raw.hasPrefix("~/") ? home + raw.dropFirst() : raw
            // Relative paths are refused: relative to what, would be the model's choice.
            guard expanded.hasPrefix("/") else { return nil }
            let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
            return .file(resolved)
        case .url:
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = url.host?.lowercased(), !host.isEmpty else { return nil }
            // The origin is what can be allowed; the path and the query stay out of permissions and logs.
            return ResourceRef(.url, "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")")
        case .account, .yumi:
            return ResourceRef(resource.kind, raw.lowercased())
        case .command:
            return ResourceRef(.command, raw.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        case .unknown:
            return ResourceRef(.unknown, raw)
        }
    }

    // MARK: - What is never ordinary

    /// Secrets and the system. Compared without case: the Mac's disk ignores it.
    private func isSensitive(_ resource: ResourceRef) -> Bool {
        guard resource.kind == .file else { return false }
        let path = resource.identifier.lowercased()
        let home = self.home.lowercased()
        let folders = [".ssh", ".gnupg", ".aws", ".kube", ".docker", ".config/gh", ".netrc",
                       "library/keychains", "library/cookies", "library/application support/com.apple.tcc"]
            .map { home + "/" + $0 }
        let system = ["/system", "/library", "/usr", "/bin", "/sbin", "/etc", "/private", "/var", "/applications", "/cores"]
        if path == "/" || path == home { return true }
        if (folders + system).contains(where: { Self.path(path, isInside: $0) }) { return true }
        let name = (path as NSString).lastPathComponent
        let secretNames = [".env", "id_rsa", "id_ed25519", "id_ecdsa", "credentials", ".npmrc", ".pypirc", "keychain"]
        let secretExtensions = ["pem", "p12", "pfx", "keychain-db", "mobileprovision"]
        return secretNames.contains(where: { name == $0 || name.hasPrefix($0 + ".") })
            || secretExtensions.contains((name as NSString).pathExtension)
    }

    /// A command is medium when every part is a known, local, undoable one; high otherwise;
    /// critical when it reaches for privileges, the disk or the keychain.
    private func commandRisk(_ resources: [ResourceRef]) -> RiskLevel {
        var risk = RiskLevel.medium
        for resource in resources where resource.kind == .command {
            let line = resource.identifier.lowercased()
            let critical = ["sudo ", "su ", "rm -rf /", "rm -rf ~", "mkfs", "dd if=", "diskutil erase", "security ",
                            "csrutil", "launchctl ", "chmod -r 777 /", ":(){"]
            if line.hasPrefix("sudo") || critical.contains(where: { line.contains($0) }) { return .critical }
            // Chained or substituted commands hide what really runs.
            let hidden = ["`", "$(", ";", "&&", "||", "|", ">", "<", "\n"]
            let first = line.split(separator: " ").first.map(String.init) ?? ""
            let known = ["ls", "pwd", "cat", "head", "tail", "wc", "grep", "rg", "find", "echo", "swift", "xcodebuild",
                         "xcodegen", "make", "npm", "pnpm", "yarn", "node", "python3", "pytest", "cargo", "go", "git"]
            let gitLocal = ["git status", "git diff", "git log", "git show", "git add", "git commit", "git branch",
                            "git switch", "git checkout", "git stash", "git fetch"]
            let isKnown = known.contains(first) && (first != "git" || gitLocal.contains(where: { line.hasPrefix($0) }))
            if hidden.contains(where: { line.contains($0) }) || !isKnown { risk = .high }
        }
        return risk
    }

    /// The closest folder above `path` (itself included) that holds a `.git`.
    static let gitRoot: @Sendable (String) -> String? = { path in
        var url = URL(fileURLWithPath: path)
        let manager = FileManager.default
        while url.path != "/" {
            if manager.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
