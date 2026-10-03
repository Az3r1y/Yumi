import Foundation

// MARK: - Driving Claude Code from the chat
// The chat talks to the Claude Code installed on the Mac instead of the billed API: one
// `claude` process per message, non-interactive, with structured input and output, and the
// same session resumed from one message to the next. Everything here is pure: where the
// binary is, which arguments and environment it gets. `ClaudeService` runs the process.

enum ClaudeCLI {
    /// Folders where Claude Code installs itself. An app launched from the Finder does not
    /// have the PATH of the terminal, so these are checked after the PATH it does have.
    static func usualFolders(home: String) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.claude/local", "\(home)/.local/bin"]
    }

    /// Path of the `claude` binary, or nil when Claude Code is not installed.
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                       home: String = NSHomeDirectory(),
                       isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (fromPath + usualFolders(home: home))
            .map { $0.hasSuffix("/") ? "\($0)claude" : "\($0)/claude" }
            .first(where: isExecutable)
    }

    /// Which conversation a message belongs to.
    enum Session: Equatable, Sendable {
        /// First message: the session is created with this identifier.
        case new(String)
        /// Later messages: the session is resumed.
        case resume(String)

        var id: String {
            switch self {
            case .new(let id), .resume(let id): return id
            }
        }
    }

    /// Arguments of one message.
    ///
    /// `--permission-prompt-tool stdio` is what makes permissions work without a terminal: in plain
    /// `-p` mode a tool that needs permission is refused on the spot and no hook is called. With it,
    /// Claude Code sends each request on stdout (`control_request`) and waits for the answer on
    /// stdin, which is why the input is `stream-json` and stays open during the turn.
    /// `--permission-mode default` is explicit so that nothing is ever accepted without being asked.
    /// `ChatTools.arguments` leaves the chat only tools that read.
    static func arguments(session: Session, systemPrompt: String, readableFolders: [String] = [],
                          extra: [String] = []) -> [String] {
        var arguments = ["-p",
                         "--input-format", "stream-json",
                         "--output-format", "stream-json",
                         "--verbose",
                         "--include-partial-messages",
                         "--permission-prompt-tool", "stdio",
                         "--permission-mode", "default"]
        switch session {
        case .new(let id):    arguments += ["--session-id", id]
        case .resume(let id): arguments += ["--resume", id]
        }
        arguments += ["--append-system-prompt", systemPrompt]
        // The chat talks and reads; acting on the Mac is the agent runtime's (ChatTools).
        arguments += ChatTools.arguments
        for folder in readableFolders { arguments += ["--add-dir", folder] }
        return arguments + extra
    }

    /// Environment of the `claude` process, built from the app's.
    /// - PATH gains the usual tool folders: Claude Code runs commands with the PATH it is given.
    /// - API credentials are removed, so that the user's subscription is used, never a billed key.
    /// - Markers of an enclosing Claude Code session are removed (the app may have been launched from one).
    static func environment(from base: [String: String], binary: String, home: String = NSHomeDirectory()) -> [String: String] {
        var environment = base
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            environment[key] = nil
        }
        let binaryFolder = (binary as NSString).deletingLastPathComponent
        let wanted = [binaryFolder] + usualFolders(home: home) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var path = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        for folder in wanted where !path.contains(folder) { path.append(folder) }
        environment["PATH"] = path.joined(separator: ":")
        environment["HOME"] = base["HOME"] ?? home
        return environment
    }
}

// MARK: - Where the chat works

enum ChatFolder {
    /// UserDefaults key of the folder Claude Code works in.
    static let key = "chatFolder"

    /// The user's Downloads folder, as the system knows it.
    static var downloads: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    /// The folder chosen by the user, their Downloads folder otherwise: what the chat creates
    /// lands where files usually arrive.
    static func path(stored: String?, home: String = NSHomeDirectory(), downloads: String = ChatFolder.downloads) -> String {
        let chosen = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty else { return downloads }
        if chosen == "~" { return home }
        if chosen.hasPrefix("~/") { return home + chosen.dropFirst(1) }
        return chosen
    }
    /// True when `path` is `folder` or inside it. Compares path components, not characters.
    static func contains(_ path: String, in folder: String) -> Bool {
        let inner = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let outer = URL(fileURLWithPath: folder).standardizedFileURL.pathComponents
        return inner.count >= outer.count && Array(inner.prefix(outer.count)) == outer
    }
}

// MARK: - Sessions started by the chat

/// Identifiers of the Claude Code sessions the chat itself started. The hook server asks it, from
/// its socket threads, which hooks to leave alone: the chat follows its own session through the
/// process output, and answers its permission requests there.
final class ChatSessionRegistry: @unchecked Sendable {
    static let shared = ChatSessionRegistry()

    private let lock = NSLock()
    private var ids: Set<String> = []

    func insert(_ id: String) { lock.withLock { _ = ids.insert(id) } }
    func remove(_ id: String) { lock.withLock { _ = ids.remove(id) } }
    func contains(_ id: String) -> Bool { lock.withLock { ids.contains(id) } }
}
