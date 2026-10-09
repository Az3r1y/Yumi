import Foundation

/// What Claude Code may do when it answers in the chat: read, search, look things up. Never
/// change the Mac: creating, editing, deleting files and running commands belong to Yumi's
/// agent runtime, where every action goes through the permission manager and is verified.
///
/// Three locks, so that none of them alone has to hold:
/// - `--tools` keeps only these built-in tools: the others do not exist for the model;
/// - `--disallowedTools` names the ones that change the Mac, which wins over any allow rule
///   of the person's own Claude Code settings;
/// - `--strict-mcp-config` without a config loads no MCP server, whose tools could write.
/// And a permission request for any other tool is refused on the spot (`mayUse`).
enum ChatTools {
    /// Built-in Claude Code tools that only look.
    static let conversational = ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]
    /// Built-in tools that change the Mac or start other agents.
    static let refused = ["Bash", "Edit", "Write", "NotebookEdit", "Task"]

    static var arguments: [String] {
        ["--tools", conversational.joined(separator: ","),
         "--disallowedTools", refused.joined(separator: ","),
         "--strict-mcp-config",
         // None of the person's settings: their allow rules would let Read or WebFetch run unasked.
         "--setting-sources", ""]
    }

    /// Whether a permission request of the chat may even be shown to the person.
    static func mayUse(_ toolName: String) -> Bool { conversational.contains(toolName) }
}
