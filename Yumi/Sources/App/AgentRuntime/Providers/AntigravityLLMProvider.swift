import Foundation

/// `LLMProvider` over Google's Antigravity CLI (`agy`), with the person's own Google login and
/// subscription. It answers, searches the web, and changes nothing:
/// - `--mode plan`: Antigravity's read-only mode (never with `--disable-slash-commands`, which
///   turns it off);
/// - `--sandbox`: the terminal restricted;
/// - headless (`-p`): any tool that needs a permission is denied, no one is there to grant it
///   (checked: a command and a file write are refused, nothing is created);
/// - it runs in an empty folder of Yumi's.
/// A plan is kept to the tools' ids and exact arguments by `--json-schema`, and goes through
/// `PlanValidator` like any other engine's.
///
/// Unlike Claude Code, `agy` has no switch to leave the person's own settings out: an allow rule,
/// a hook, an MCP server or a plugin of theirs would act in Yumi's session too, where a page met
/// in a search could steer it. So it is only used while none is set (`isolationProblem`): then
/// the web search alone is left, and it goes to Google, which has the request anyway.
struct AntigravityLLMProvider: LLMProvider {
    typealias Runner = @Sendable (_ binary: String, _ arguments: [String], _ folder: String) async throws -> (output: Data, errors: Data)

    static let defaultModel = "gemini-3.8-flash-medium"

    var binary: @Sendable () -> String? = { AntigravityLLMProvider.find() }
    var folder: String
    var model: String?
    var runner: Runner = AntigravityLLMProvider.runProcess
    var timeout: Duration = .seconds(150)

    var name: String { "antigravity:\(model ?? Self.defaultModel)" }

    /// Where `agy` is installed, or nil.
    static func find(home: String = NSHomeDirectory()) -> String? {
        let candidates = [home + "/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func arguments(prompt: String, model: String, schema: String?) -> [String] {
        var arguments = ["-p", prompt, "--mode", "plan", "--sandbox", "--output-format", "json",
                         "--model", model, "--print-timeout", "140s"]
        if let schema { arguments += ["--json-schema", schema] }
        return arguments
    }

    /// Antigravity's own folder of settings.
    var configFolder: String = NSHomeDirectory() + "/.gemini/antigravity-cli"
    /// The hooks file that may stay: the one Yumi wrote itself, exactly.
    var isOwnHooks: @Sendable (Any) -> Bool = { _ in false }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let binary = binary() else { throw LLMProviderError.unavailable }
        if let problem = Self.isolationProblem(in: configFolder, isOwnHooks: isOwnHooks) { throw LLMProviderError.failed(problem) }
        // No flag for the rules: they open the prompt
        let prompt = request.system + "\n\n" + AppleLLMProvider.prompt(request.messages, budget: 60_000)
        let schema = request.expectsJSON ? request.tools.flatMap(Self.planSchema) : nil
        let arguments = Self.arguments(prompt: prompt, model: model ?? Self.defaultModel, schema: schema)
        let result: (output: Data, errors: Data)
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            result = try await withThrowingTaskGroup(of: (output: Data, errors: Data)?.self) { group in
                group.addTask { [runner, folder] in try await runner(binary, arguments, folder) }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let done = first else { throw LLMProviderError.failed("Antigravity did not answer in time") }
                return done
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.failed("Antigravity did not run")
        }
        return try Self.read(result.output, errors: result.errors)
    }

    /// What, in the person's Antigravity settings, would act without asking in Yumi's session;
    /// nil when nothing does.
    /// Settings known to change nothing of what the session may do. Any other one blocks: what
    /// Yumi does not know, it does not let through.
    static let harmlessSettings: Set<String> = ["trustedWorkspaces", "model"]
    /// Where an administrator's settings for Antigravity would be.
    static let adminSettings = "/Library/Application Support/Antigravity/admin_settings.json"

    static func isolationProblem(in folder: String, isOwnHooks: (Any) -> Bool,
                                 adminSettings: String = AntigravityLLMProvider.adminSettings) -> String? {
        let manager = FileManager.default
        let unreadable = loc("Antigravity : je n'arrive pas à lire tes réglages, je ne l'utilise donc pas comme moteur de Yumi.")
        /// .missing, .value, or nil when the file is there but unreadable: then nothing is assumed.
        enum File { case missing, value(Any) }
        func read(_ name: String) -> File? {
            let path = folder + "/" + name
            guard manager.fileExists(atPath: path) else { return .missing }
            guard let data = manager.contents(atPath: path) else { return nil }
            if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return .missing }
            return (try? JSONSerialization.jsonObject(with: data)).map(File.value)
        }
        if manager.fileExists(atPath: adminSettings) {
            return loc("Antigravity : des réglages d'administration s'appliquent, je ne l'utilise donc pas comme moteur de Yumi.")
        }
        // Settings: only the harmless keys, a file it cannot read the way Antigravity might counting as unsafe
        guard let settingsFile = read("settings.json") else { return unreadable }
        // Other files of settings Antigravity might read
        for other in ["settings.local.json", "settings.jsonc", "settings.json5"] where manager.fileExists(atPath: folder + "/" + other) {
            return loc("Antigravity : tes réglages contiennent \(other), qui pourrait agir sans demander. Retire-le pour l'utiliser comme moteur de Yumi.")
        }
        if case .value(let value) = settingsFile {
            guard let settings = value as? [String: Any] else { return unreadable }
            // The harmless keys only with their harmless form: a list of folders, a model's name
            if let folders = settings["trustedWorkspaces"], !(folders is [String]) { return unreadable }
            if let model = settings["model"], !(model is String) { return unreadable }
            let unknown = settings.keys.filter { !harmlessSettings.contains($0) }.sorted()
            if !unknown.isEmpty {
                return loc("Antigravity : tes réglages contiennent \(unknown.joined(separator: ", ")), qui pourrait agir sans demander. Retire-le pour l'utiliser comme moteur de Yumi.")
            }
        }
        guard let hooksFile = read("hooks.json") else { return unreadable }
        // Only none, or exactly Yumi's: a hook has more forms than Yumi can tell apart
        if case .value(let hooks) = hooksFile, !((hooks as? [String: Any])?.isEmpty ?? false), !isOwnHooks(hooks) {
            return loc("Antigravity : des hooks à toi tourneraient aussi pour Yumi. Retire-les pour l'utiliser comme moteur.")
        }
        guard let mcpFile = read("mcp_config.json") else { return unreadable }
        // Only nothing, or an empty list of servers in the form expected
        if case .value(let mcp) = mcpFile, !Self.isEmptyMCP(mcp) {
            return loc("Antigravity : des serveurs MCP sont configurés. Retire-les pour l'utiliser comme moteur de Yumi.")
        }
        let plugins = (try? manager.contentsOfDirectory(atPath: folder + "/plugins"))?.filter { !$0.hasPrefix(".") } ?? []
        if !plugins.isEmpty { return loc("Antigravity : des plugins sont installés. Retire-les pour l'utiliser comme moteur de Yumi.") }
        return nil
    }

    /// `{}` or `{"mcpServers": {}}`, nothing else.
    private static func isEmptyMCP(_ value: Any) -> Bool {
        guard let object = value as? [String: Any] else { return false }
        if object.isEmpty { return true }
        guard object.count == 1, let servers = object["mcpServers"] as? [String: Any] else { return false }
        return servers.isEmpty
    }

    /// The answer: the structured output of a plan (an empty `cannotPlan` dropped, it is not a
    /// refusal), or the text.
    static func read(_ output: Data, errors: Data) throws -> LLMResponse {
        guard let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            let said = String(decoding: errors, as: UTF8.self)
            if said.localizedCaseInsensitiveContains("sign in") { throw LLMProviderError.unavailable }
            throw LLMProviderError.failed("unreadable answer from Antigravity")
        }
        if var structured = object["structured_output"] as? [String: Any] {
            if (structured["cannotPlan"] as? String)?.nonEmptyTrimmed == nil { structured["cannotPlan"] = nil }
            if structured["steps"] != nil, structured["cannotPlan"] == nil { structured["isAction"] = nil }
            if let data = try? JSONSerialization.data(withJSONObject: structured) {
                return LLMResponse(text: String(decoding: data, as: UTF8.self))
            }
        }
        guard let text = (object["response"] as? String)?.nonEmptyTrimmed else {
            throw LLMProviderError.failed("empty answer from Antigravity")
        }
        return LLMResponse(text: text)
    }

    /// The plan as `PlanProposal` reads it, in JSON Schema: each step one of the tools with
    /// exactly its arguments, or the reason no plan fits.
    static func planSchema(_ tools: [ToolDescriptor]) -> String? {
        let steps: [[String: Any]] = tools.map { tool in
            var properties: [String: Any] = [:]
            for field in tool.inputSchema.fields {
                let type = switch field.type { case .string: "string"; case .number: "number"; case .bool: "boolean" }
                properties[field.name] = ["type": type, "description": field.description]
            }
            return ["type": "object", "description": tool.description, "additionalProperties": false,
                    "required": ["description", "tool", "arguments"],
                    "properties": [
                        "description": ["type": "string"],
                        "tool": ["type": "string", "enum": [tool.id]],
                        "arguments": ["type": "object", "properties": properties, "additionalProperties": false,
                                      "required": tool.inputSchema.fields.filter(\.required).map(\.name)],
                    ]]
        }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": [
                "goal": ["type": "string"],
                "steps": ["type": "array", "items": ["anyOf": steps]],
                "cannotPlan": ["type": "string", "description": "only when no plan fits: why"],
                "isAction": ["type": "boolean"],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
    }

    static let runProcess: Runner = { binary, arguments, folder in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        // Nothing of the person's environment may set Antigravity up differently from what was checked
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("ANTIGRAVITY_") && !$0.key.hasPrefix("AGY_") }
        let stdout = Pipe(), stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        return try await withTaskCancellationHandler {
            async let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
            async let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
            let result = await (output, errors)
            process.waitUntilExit()
            try Task.checkCancellation()
            return result
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
