import Foundation

/// Turns what an Antigravity hook sends (relayed with `source: "antigravity"`) into `YumiEvent`s.
/// Antigravity asks nothing through its hooks here: its sessions are only shown.
enum AntigravityHookTranslator {
    static let agent = Agent(id: AgentID("antigravity"), name: "Antigravity", kind: .coding)

    /// - Parameter ownFolder: Yumi's own folder. The sessions of Yumi's engine and search run
    ///   there: they are Yumi talking, not the person's work.
    static func events(for payload: [String: Any], ownFolder: String = AppIdentity.supportDirectory.path) -> [YumiEvent] {
        guard let conversation = payload["conversationId"] as? String, !conversation.isEmpty else { return [] }
        let cwd = (payload["workspacePaths"] as? [String])?.first ?? ""
        if !cwd.isEmpty, (cwd + "/").hasPrefix(ownFolder + "/") { return [] }
        let id = SessionID("agy-" + conversation)

        var specific: [YumiEvent] = []
        switch payload["hook_event_name"] as? String {
        case "PreInvocation":
            // A new turn: the first call of one answer
            guard payload["invocationNum"] as? Int == 0 else { break }
            specific = [.promptSubmitted(id, text: "")]
        case "PreToolUse":
            specific = [.toolStarted(id, tool(payload))]
        case "PostToolUse":
            specific = [.toolFinished(id, tool(payload))]
            if let error = payload["error"] as? String, !error.isEmpty { specific.append(.activityNoted(id, loc("Échec"))) }
        case "Stop":
            if let error = payload["error"] as? String, !error.isEmpty {
                specific = [.sessionErrored(id, YumiError(message: String(error.prefix(120))))]
            } else {
                specific = [.taskCompleted(id)]
            }
        default:
            return []
        }
        return [.sessionStarted(id, agent, title: ClaudeHookTranslator.projectName(forDirectory: cwd)),
                // The relay adds the terminal `agy` runs in, as for Claude Code
                .sessionLocated(id, SessionOrigin(workingDirectory: cwd, hostBundleID: payload["bundle_id"] as? String ?? "",
                                                  hostName: payload["term_program"] as? String ?? ""))] + specific
    }

    /// "Read a.txt": Antigravity's own short description of the call.
    private static func tool(_ payload: [String: Any]) -> ToolInfo {
        let call = payload["toolCall"] as? [String: Any] ?? [:]
        let arguments = call["args"] as? [String: Any] ?? [:]
        let summary = (arguments["toolSummary"] as? String) ?? (arguments["toolAction"] as? String) ?? ""
        return ToolInfo(name: call["name"] as? String ?? "Tool", summary: String(summary.prefix(60)))
    }
}

/// Yumi's hooks in Antigravity's `hooks.json`: one named entry, `yumi`, for the four events
/// that tell what a session does. Nothing is written before the person has read the change.
enum AntigravityHooks {
    static let name = "yumi"
    static let events = ["PreInvocation", "PreToolUse", "PostToolUse", "Stop"]
    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.gemini/antigravity-cli/hooks.json")
    }

    /// The command for one event: the same relay as Claude Code's, told where the payload comes from.
    static func command(_ event: String, script: String = AppIdentity.hookScriptPath) -> String {
        let quoted = "\"" + script.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        return "YUMI_HOOK_SOURCE=antigravity YUMI_HOOK_EVENT=\(event) /bin/sh \(quoted)"
    }

    static func spec(script: String = AppIdentity.hookScriptPath) -> [String: Any] {
        var spec: [String: Any] = [:]
        for event in events {
            let hook: [String: Any] = ["type": "command", "command": command(event, script: script), "timeout": 5]
            // Tool events are grouped by matcher, the others are a plain list
            spec[event] = event.hasSuffix("ToolUse") ? [["matcher": "*", "hooks": [hook]]] : [hook]
        }
        return spec
    }

    /// True when the whole file is Yumi's entry, exactly: then Antigravity can still be Yumi's engine.
    static func isOwn(_ hooks: Any, script: String = AppIdentity.hookScriptPath) -> Bool {
        (hooks as? NSDictionary)?.isEqual(to: [name: spec(script: script)]) ?? false
    }

    static func isInstalled(_ data: Data?, script: String = AppIdentity.hookScriptPath) -> Bool {
        guard let data, let hooks = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = hooks[name] else { return false }
        return (entry as? NSDictionary)?.isEqual(to: spec(script: script)) ?? false
    }

    /// The file with Yumi's entry set, the others kept.
    static func install(_ data: Data?, script: String = AppIdentity.hookScriptPath) throws(HookSettings.Problem) -> Data {
        var hooks = try read(data)
        hooks[name] = spec(script: script)
        return try encode(hooks)
    }

    /// The file without Yumi's entry.
    static func remove(_ data: Data?) throws(HookSettings.Problem) -> Data {
        var hooks = try read(data)
        hooks[name] = nil
        return try encode(hooks)
    }

    private static func read(_ data: Data?) throws(HookSettings.Problem) -> [String: Any] {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw .notJSON }
        guard let hooks = object as? [String: Any] else { throw .notAnObject }
        return hooks
    }

    private static func encode(_ hooks: [String: Any]) throws(HookSettings.Problem) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: hooks, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { throw .notJSON }
        return data
    }

    // MARK: On disk

    static var isInstalled: Bool { isInstalled(try? Data(contentsOf: fileURL)) }

    /// Writes `data` after a dated copy of the current file.
    static func write(_ data: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: fileURL.path) {
            try manager.copyItem(at: fileURL, to: HookSettings.backupURL(for: fileURL, now: Date()) { manager.fileExists(atPath: $0.path) })
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
