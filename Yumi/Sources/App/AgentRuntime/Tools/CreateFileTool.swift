import Foundation

/// Creates one new text file in a folder Yumi may write to: Downloads (where a bare file name
/// goes), the Desktop and Documents. Never replaces a file that exists, never creates a folder, never writes a hidden
/// file. Whether it may run at all is the permission system's call: this tool only describes
/// the action (`action(for:)`) and refuses what it was not made for.
struct CreateFileTool: Tool {
    static let maxBytes = 100_000

    /// The folders a file may be created in, directly or below. Absolute, without `~`.
    var allowedFolders: [String]
    var home: String

    init(home: String = NSHomeDirectory(), allowedFolders: [String]? = nil) {
        self.home = home
        self.allowedFolders = allowedFolders ?? ["Downloads", "Desktop", "Documents"].map { (home as NSString).appendingPathComponent($0) }
    }

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "create_file",
            name: "Create a file",
            description: "Creates a new text file with the given content, in ~/Downloads unless the person names ~/Desktop or ~/Documents; never replaces an existing file.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "path", type: .string, required: true,
                      description: "~/Downloads/<name> by default (~/Downloads/todo.md); ~/Desktop/<name> or ~/Documents/<name> only when the person asks for that place"),
                .init(name: "content", type: .string, required: true, description: "the full text of the file"),
            ]),
            risk: .write,
            outputKeys: ["path", "bytes"])
    }

    func action(for arguments: ToolArguments) -> ToolAction? {
        guard case .string(let raw)? = arguments["path"] else { return nil }
        return ToolAction(kind: .create, resources: [.file(expand(raw))], reversible: true)
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        guard case .string(let raw)? = arguments["path"], case .string(let content)? = arguments["content"] else {
            throw ToolError.invalidInput("path and content are required")
        }
        let path = try destination(for: raw)
        let data = Data(content.utf8)
        guard data.count <= Self.maxBytes else { throw ToolError.invalidInput("the content is larger than \(Self.maxBytes) bytes") }
        try Task.checkCancellation()
        do {
            try data.write(to: URL(fileURLWithPath: path), options: [.withoutOverwriting])
        } catch CocoaError.fileWriteFileExists {
            throw ToolError.invalidInput("\(display(path)) already exists")
        } catch {
            throw ToolError.failed("could not write \(display(path))")
        }
        return ToolOutput(summary: "Created \(display(path)).",
                          values: ["path": .string(path), "bytes": .number(Double(data.count))])
    }

    /// The file is there, and holds exactly what was asked.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let path)? = output.values["path"], case .string(let content)? = arguments["content"] else {
            return "no path to check"
        }
        guard let written = FileManager.default.contents(atPath: path) else { return "\(display(path)) does not exist" }
        return written == Data(content.utf8) ? nil : "\(display(path)) does not hold the expected content"
    }

    // MARK: - Paths

    /// The absolute path the file will have, or why not.
    func destination(for raw: String) throws(ToolError) -> String {
        let expanded = expand(raw)
        guard expanded.hasPrefix("/") else { throw .invalidInput("the path must start with ~/Downloads/, ~/Desktop/ or ~/Documents/") }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let name = url.lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), name != "/" else { throw .invalidInput("\(name) is not a usable file name") }
        // The folder is resolved (symbolic links included); the file itself does not exist yet.
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let roots = allowedFolders.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        guard roots.contains(where: { RiskAssessor.path(folder, isInside: $0) }) else {
            throw .invalidInput("Yumi can only create files in Downloads, on the Desktop or in Documents")
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
            throw .invalidInput("the folder \(display(folder)) does not exist")
        }
        return (folder as NSString).appendingPathComponent(name)
    }

    /// The default folder: where a bare file name (`todo.md`) is created.
    var defaultFolder: String { (home as NSString).appendingPathComponent("Downloads") }

    /// `~/x` from the home folder; a bare name in the default folder; anything else as given (a
    /// relative path with folders is refused later). The permission request shows the result.
    private func expand(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if !trimmed.isEmpty, !trimmed.contains("/"), trimmed != "..", trimmed != "." {
            return (defaultFolder as NSString).appendingPathComponent(trimmed)
        }
        return trimmed.hasPrefix("~/") ? home + trimmed.dropFirst() : trimmed
    }

    /// `~/Desktop/todo.md`: the home folder is not repeated in summaries and errors.
    private func display(_ path: String) -> String {
        RiskAssessor.path(path, isInside: home) ? "~" + path.dropFirst(home.count) : path
    }
}
