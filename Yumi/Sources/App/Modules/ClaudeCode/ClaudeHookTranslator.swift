import Foundation

/// Turns the JSON a Claude Code hook sends into `YumiEvent`s. This is the only place
/// that knows the hook format; everything after it works on typed events.
enum ClaudeHookTranslator {
    static let agent = Agent(id: AgentID("claude-code"), name: "Claude Code", kind: .coding)

    /// Events for one hook payload, in the order they must be applied.
    /// - Parameter requestID: identifier given to a `PermissionRequest`, so its answer can be routed back.
    static func events(for payload: [String: Any], requestID: String = UUID().uuidString) -> [YumiEvent] {
        let name = payload["hook_event_name"] as? String ?? ""
        let id = SessionID(payload["session_id"] as? String ?? "unknown")

        if name == "SessionEnd" { return [.sessionEnded(id)] }

        var specific: [YumiEvent] = []
        switch name {
        case "SessionStart":
            break

        case "UserPromptSubmit":
            specific = [.promptSubmitted(id, text: payload["prompt"] as? String ?? "")]

        case "PreToolUse":
            specific = [.toolStarted(id, tool(from: payload))]

        case "PostToolUse":
            specific = [.toolFinished(id, tool(from: payload))]

        case "PostToolUseFailure":
            specific = [.toolFinished(id, tool(from: payload)), .activityNoted(id, loc("Échec"))]

        case "PermissionRequest":
            let tool = payload["tool_name"] as? String ?? "Tool"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let command = input["command"] as? String ?? tool
            specific = [.permissionRequested(id, PermissionRequest(id: requestID, tool: tool, command: command))]

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let lower = message.lowercased()
            if lower.contains("rate limit") || lower.contains("limite d") {
                specific = [.rateLimited(id)]
            } else if message.hasSuffix("?") {
                specific = [.questionRequested(id, Question(text: message))]
            }

        case "Stop":
            if let message = payload["message"] as? String, !message.isEmpty {
                specific = [.activityNoted(id, String(message.prefix(60)))]
            }
            specific.append(.taskCompleted(id))

        case "StopFailure":
            specific = [.sessionErrored(id, YumiError(message: payload["message"] as? String ?? ""))]

        case "SubagentStart":
            specific = [.activityNoted(id, loc("Un sous-agent démarre"))]

        case "SubagentStop":
            specific = [.activityNoted(id, loc("Un sous-agent a fini"))]

        default:
            return []
        }

        // Every hook introduces its session: Yumi may have been launched after it started.
        // The store ignores a start it already knows.
        let cwd = payload["cwd"] as? String ?? ""
        let origin = SessionOrigin(workingDirectory: cwd,
                                   hostBundleID: payload["bundle_id"] as? String ?? "",
                                   hostName: payload["term_program"] as? String ?? "")
        return [.sessionStarted(id, agent, title: projectName(forDirectory: cwd)),
                .sessionLocated(id, origin)] + specific
    }

    /// Version of the reply protocol the hook script speaks. Scripts written before version 2
    /// do not send it and do not expect an acknowledgement.
    static func protocolVersion(of payload: [String: Any]) -> Int {
        payload["hook_protocol"] as? Int ?? 1
    }

    static func projectName(forDirectory directory: String) -> String {
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return directory.isEmpty || name.isEmpty || name == "/" ? "Session" : name
    }

    private static func tool(from payload: [String: Any]) -> ToolInfo {
        let name = payload["tool_name"] as? String ?? "Tool"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        return ToolInfo(name: name, summary: detail(of: input))
    }

    /// The part of a tool input worth showing: the command, the file name or the query.
    private static func detail(of input: [String: Any]) -> String {
        if let command = input["command"] as? String {
            return String(command.prefix(40))
        } else if let path = input["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        } else if let file = input["file_path"] as? String {
            return URL(fileURLWithPath: file).lastPathComponent
        } else if let query = input["query"] as? String {
            return String(query.prefix(40))
        }
        return ""
    }
}

/// The wording for the tools Claude Code runs, in the language Yumi speaks.
enum ClaudeToolPhrase {
    /// Computed each time: the words follow the language Yumi speaks.
    private static var labels: [String: String] {
        [
            "Bash":       loc("Exécute"),
            "Read":       loc("Lit"),
            "Write":      loc("Écrit"),
            "Edit":       loc("Modifie"),
            "Glob":       loc("Cherche"),
            "Grep":       loc("Recherche"),
            "WebSearch":  loc("Recherche web"),
            "WebFetch":   loc("Récupère"),
            "TodoWrite":  loc("Tâches"),
            "Task":       loc("Agent"),
            "LS":         loc("Liste"),
            "MultiEdit":  loc("Modifie"),
            "NotebookEdit": loc("Notebook"),
        ]
    }

    static func label(for tool: String) -> String { labels[tool] ?? tool }

    /// One line of the activity log: "Modifie · main.swift".
    static func step(_ tool: ToolInfo) -> String {
        let label = label(for: tool.name)
        return tool.summary.isEmpty ? label : "\(label) · \(tool.summary)"
    }

    /// The same, as the end of a sentence: "modifie main.swift".
    static func sentence(_ tool: ToolInfo) -> String {
        let label = label(for: tool.name)
        let lowered = label.prefix(1).lowercased() + label.dropFirst()
        return tool.summary.isEmpty ? lowered : "\(lowered) \(tool.summary)"
    }
}
