import Foundation

/// `LLMProvider` over the Claude Code installed on the Mac, used as a model only: it reads the
/// runtime's request and answers text, nothing else. It uses the person's own Claude Code login
/// (their subscription or whatever billing it is set up with), never a key of Yumi's.
///
/// What makes it a model and not an agent (`arguments`):
/// - `--tools ""`: no built-in tool at all (no shell, no file, no web);
/// - `--strict-mcp-config` without a config: no MCP server;
/// - `--setting-sources ""`: none of the person's settings, so no hooks, no allow rules, no plugins;
/// - `--disable-slash-commands`: no skill;
/// - `--system-prompt`: the runtime's rules replace Claude Code's own agent prompt;
/// - `--no-session-persistence`: nothing is kept after the answer;
/// - it runs in an empty folder, so no CLAUDE.md is read.
/// Its answer goes through `PlanValidator` like any other model's.
struct ClaudeCodeLLMProvider: LLMProvider {
    /// Runs the binary with these arguments, the request on standard input, and returns standard output.
    typealias Runner = @Sendable (_ binary: String, _ arguments: [String], _ input: Data, _ folder: String) async throws -> Data

    /// Where `claude` is, or nil when it is not installed.
    var binary: @Sendable () -> String?
    /// An empty folder the process runs in.
    var folder: String
    var model: String?
    var runner: Runner = ClaudeCodeLLMProvider.runProcess
    /// Built-in tools it may use without asking, read-only ones only (`WebSearch` for a search).
    /// None by default: a model, not an agent.
    var readOnlyTools: [String] = []
    /// A planner that does not answer in this time is stopped: a request never waits forever.
    var timeout: Duration = .seconds(120)

    var name: String { "claude-code" }

    /// Only tools that read and leave the Mac nothing to change: a search engine's.
    static let readOnly: Set<String> = ["WebSearch"]

    static func arguments(system: String, model: String?, tools: [String] = []) -> [String] {
        let tools = tools.filter(readOnly.contains)
        var arguments = ["-p", "--output-format", "json", "--no-session-persistence",
                         "--tools", tools.joined(separator: ","), "--strict-mcp-config", "--disable-slash-commands",
                         "--setting-sources", "", "--permission-mode", "default",
                         "--system-prompt", system]
        if let model { arguments += ["--model", model] }
        if !tools.isEmpty { arguments += ["--allowedTools", tools.joined(separator: ",")] }
        return arguments
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let binary = binary() else { throw LLMProviderError.unavailable }
        // One turn: the messages become one text, as the runtime only ever sends one.
        let text = request.messages.map(\.content).joined(separator: "\n\n")
        let output: Data
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            output = try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask { [runner, model, folder] in
                    try await runner(binary, Self.arguments(system: request.system, model: model, tools: readOnlyTools), Data(text.utf8), folder)
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let data = first else { throw TimedOut() }
                return data
            }
        } catch is TimedOut {
            throw LLMProviderError.failed("Claude Code did not answer in time")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMProviderError.failed("Claude Code did not run")
        }
        guard let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw LLMProviderError.failed("unreadable answer from Claude Code")
        }
        if object["is_error"] as? Bool == true {
            // Not logged in: as if Claude Code were not there, so the next provider (the API key)
            // can plan, and the chat says how to log in.
            let said = ([object["result"] as? String ?? ""] + (object["errors"] as? [String] ?? [])).joined(separator: " ")
            if ChatPhrases.isLoginProblem(said) { throw LLMProviderError.unavailable }
            // No quota… The text can quote the request: only the kind is kept.
            throw LLMProviderError.failed("Claude Code: \(object["subtype"] as? String ?? "error")")
        }
        guard let result = (object["result"] as? String)?.nonEmptyTrimmed else {
            throw LLMProviderError.failed("empty answer from Claude Code")
        }
        return LLMResponse(text: result)
    }

    /// Runs `claude` and waits for it, stopping it if the task is cancelled. The environment loses
    /// API credentials, so the person's Claude Code login is used, as in the chat.
    static let runProcess: Runner = { binary, arguments, input, folder in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        var environment = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            environment[key] = nil
        }
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        return try await withTaskCancellationHandler {
            let data = await Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
            process.waitUntilExit()
            try Task.checkCancellation()
            return data
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private struct TimedOut: Error {}

/// Asks each provider in turn: the next one is tried only when the previous one is not
/// configured (`unavailable`). A provider that was reached and failed is not retried
/// elsewhere: the run fails and says so.
struct FallbackLLMProvider: LLMProvider {
    var providers: [any LLMProvider]

    var name: String { providers.map(\.name).joined(separator: " > ") }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        for provider in providers {
            do {
                return try await provider.complete(request)
            } catch LLMProviderError.unavailable {
                continue
            }
        }
        throw LLMProviderError.unavailable
    }
}
