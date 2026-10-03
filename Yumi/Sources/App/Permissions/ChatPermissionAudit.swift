import Foundation

/// A permission request of the chat's Claude Code, written in the same history as the agent's
/// own decisions (`PermissionAuditLog`), so the person sees in one place everything that was
/// allowed or refused. The chat's requests are still answered by the island, not decided by
/// `LocalPermissionManager`: this only records them.
///
/// Like every entry, it keeps no argument: a file is kept by its place (`~/Downloads/a.pdf`), a
/// page by its host only, and a search or a pattern not at all.
enum ChatPermissionAudit {
    enum Outcome: Equatable, Sendable {
        /// The person clicked Autoriser, or « Toujours autoriser » (`always`).
        case approved(always: Bool)
        case denied
        /// Nobody answered in time.
        case expired
        /// A tool that changes the Mac: refused without being shown (`ChatTools.mayUse`).
        case blocked
        /// The turn ended or Claude Code withdrew the request before an answer.
        case cancelled
    }

    /// Tools that only read on the Mac. Anything else leaves it (the web) or is not expected.
    static let localTools: Set<String> = ["Read", "Glob", "Grep", "LS", "NotebookRead"]
    static let webTools: Set<String> = ["WebFetch", "WebSearch"]

    /// The island's answer to a chat request ("allow", "always", "deny", anything else when
    /// nobody answered), as an outcome.
    static func outcome(islandAnswer: String) -> Outcome {
        switch islandAnswer {
        case "allow": .approved(always: false)
        case "always": .approved(always: true)
        case "deny": .denied
        default: .expired
        }
    }

    static func entry(tool: String, input: Data, outcome: Outcome, date: Date,
                      home: String = NSHomeDirectory()) -> PermissionAuditEntry {
        let resources = resources(tool: tool, input: input, home: home)
        let (decision, decidedBy, scope): (PermissionAuditEntry.Decision, PermissionAuditEntry.DecidedBy, PermissionScope?) =
            switch outcome {
            case .approved(let always): (.approved, .user, always ? .session : .oneTime)
            case .denied: (.denied, .user, nil)
            case .expired: (.expired, .system, nil)
            case .blocked: (.blocked, .defaults, nil)
            case .cancelled: (.cancelled, .system, nil)
            }
        return PermissionAuditEntry(
            date: date, runID: nil, stepID: nil, approvalID: nil, toolID: "chat:" + tool,
            action: localTools.contains(tool) || webTools.contains(tool) ? ActionKind.read.rawValue : nil,
            resources: resources, resourceCount: resources.count, risk: risk(of: tool),
            decision: decision, scope: scope, decidedBy: decidedBy)
    }

    /// Reading on the Mac is low; reaching the web leaves the Mac; any other tool changes it.
    static func risk(of tool: String) -> RiskLevel {
        if localTools.contains(tool) { return .low }
        return .high
    }

    /// The place a request touches, and nothing of what it asks: the file or folder, the host.
    private static func resources(tool: String, input: Data, home: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { return [] }
        if let url = (object["url"] as? String).flatMap(URL.init(string:)), let host = url.host {
            return [host.lowercased()]
        }
        for key in ["file_path", "notebook_path", "path"] {
            guard let path = (object[key] as? String)?.nonEmptyTrimmed else { continue }
            let base = home.hasSuffix("/") ? String(home.dropLast()) : home
            if path == base || path.hasPrefix(base + "/") { return ["~" + path.dropFirst(base.count)] }
            return [path]
        }
        return []
    }
}
