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
    /// Where each created file is noted, so that only those can be added to later.
    var log: (any CreatedFilesLog)?

    init(home: String = NSHomeDirectory(), allowedFolders: [String]? = nil, log: (any CreatedFilesLog)? = nil) {
        self.home = home
        self.log = log
        self.allowedFolders = allowedFolders ?? ["Downloads", "Desktop", "Documents"].map { (home as NSString).appendingPathComponent($0) }
    }

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "create_file",
            name: loc("Create a file"),
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
        // The approval shows what the file will hold, not only where it goes.
        var content: String?
        if case .string(let text)? = arguments["content"] { content = text }
        return ToolAction(kind: .create, resources: [.file(expand(raw))], reversible: true, content: content)
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        guard case .string(let raw)? = arguments["path"], case .string(let content)? = arguments["content"] else {
            throw ToolError.invalidInput(loc("il manque l'emplacement ou le contenu"))
        }
        let path = try destination(for: raw)
        let data = Data(content.utf8)
        guard data.count <= Self.maxBytes else { throw ToolError.invalidInput(loc("le contenu dépasse \(Self.maxBytes / 1000) Ko")) }
        try Task.checkCancellation()
        do {
            try data.write(to: URL(fileURLWithPath: path), options: [.withoutOverwriting])
        } catch {
            throw ToolError.failed(writeFailure(error, path: path))
        }
        log?.record(path)
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

    /// Everything `execute` would refuse, checked before the person is asked.
    func check(_ arguments: ToolArguments) async -> String? {
        guard case .string(let raw)? = arguments["path"], case .string(let content)? = arguments["content"] else {
            return loc("il manque l'emplacement ou le contenu")
        }
        let path: String
        do { path = try destination(for: raw) } catch {
            if case .invalidInput(let reason) = error { return reason }
            return "emplacement impossible"
        }
        if Data(content.utf8).count > Self.maxBytes { return loc("le contenu dépasse \(Self.maxBytes / 1000) Ko") }
        if FileManager.default.fileExists(atPath: path) { return loc("\(display(path)) existe déjà, et je ne remplace jamais un fichier") }
        let folder = (path as NSString).deletingLastPathComponent
        // Listing the folder is what macOS guards for Documents, the Desktop and Downloads: a refusal
        // here is the same one the write would meet (and a signed build gets its question now).
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder)
        } catch {
            return posixCode(of: error) == .EACCES ? "je n'ai pas le droit d'ouvrir \(display(folder))" : noAccess(to: folder)
        }
        if !FileManager.default.isWritableFile(atPath: folder) { return loc("je n'ai pas le droit d'écrire dans \(display(folder))") }
        return nil
    }

    private func noAccess(to folder: String) -> String {
        loc("macOS ne me laisse pas accéder à \(display(folder)). Autorise Yumi dans Réglages Système, Confidentialité et sécurité, Fichiers et dossiers")
    }

    /// The exact reason a write failed, in words for the person.
    private func writeFailure(_ error: Error, path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        if (error as? CocoaError)?.code == .fileWriteFileExists { return loc("\(display(path)) existe déjà, et je ne remplace jamais un fichier") }
        switch posixCode(of: error) {
        case .EPERM?: return noAccess(to: folder)
        case .EACCES?: return loc("je n'ai pas le droit d'écrire dans \(display(folder))")
        case .ENOSPC?: return loc("le disque est plein")
        case .EROFS?: return loc("\(display(folder)) est en lecture seule")
        default:
            if (error as? CocoaError)?.code == .fileWriteNoPermission { return noAccess(to: folder) }
            return loc("l'écriture de \(display(path)) a échoué (\((error as NSError).domain) \((error as NSError).code))")
        }
    }

    /// The system's reason under a Foundation error. EPERM on a folder of the home is macOS's
    /// privacy protection; EACCES is the ordinary file permissions.
    private func posixCode(of error: Error) -> POSIXErrorCode? {
        let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
        guard let underlying, underlying.domain == NSPOSIXErrorDomain else { return nil }
        return POSIXErrorCode(rawValue: Int32(underlying.code))
    }

    // MARK: - Paths

    /// The absolute path the file will have, or why not.
    func destination(for raw: String) throws(ToolError) -> String {
        let expanded = expand(raw)
        guard expanded.hasPrefix("/") else { throw .invalidInput(loc("l'emplacement doit être dans Téléchargements, sur le Bureau ou dans Documents")) }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let name = url.lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), name != "/" else { throw .invalidInput(loc("« \(name) » n'est pas un nom de fichier utilisable")) }
        // The folder is resolved (symbolic links included); the file itself does not exist yet.
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let roots = allowedFolders.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        guard roots.contains(where: { RiskAssessor.path(folder, isInside: $0) }) else {
            throw .invalidInput(loc("je ne crée des fichiers que dans Téléchargements, sur le Bureau ou dans Documents, pas dans \(display(folder))"))
        }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else {
            throw .invalidInput(loc("le dossier \(display(folder)) n'existe pas"))
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
