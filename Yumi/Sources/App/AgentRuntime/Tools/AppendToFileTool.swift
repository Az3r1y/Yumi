import CryptoKit
import Foundation

/// Adds text at the end of a text file Yumi created itself (`CreatedFilesLog`), and only those.
/// Never another file, never replaces or removes what is there, never follows a link.
struct AppendToFileTool: Tool {
    static let maxCharacters = 4_000
    /// A file larger than this is not a note any more: it is left alone.
    static let maxFileBytes = 1_000_000

    var log: any CreatedFilesLog
    var home: String
    var allowedFolders: [String]

    init(log: any CreatedFilesLog, home: String = NSHomeDirectory(), allowedFolders: [String]? = nil) {
        self.log = log
        self.home = home
        self.allowedFolders = allowedFolders ?? ["Downloads", "Desktop", "Documents"].map { (home as NSString).appendingPathComponent($0) }
    }

    var descriptor: ToolDescriptor {
        let known = log.paths().suffix(10).map(display).joined(separator: ", ")
        return ToolDescriptor(
            id: "append_to_file",
            name: loc("Add to a file"),
            description: "Adds text at the end of a text file Yumi created earlier; never any other file, never replaces content. Files Yumi created: \(known.isEmpty ? "none yet" : known).",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "path", type: .string, required: true,
                      description: "one of the files Yumi created, as listed (~/Downloads/todo.md), or its name alone"),
                .init(name: "text", type: .string, required: true,
                      description: "the text to add at the end, as the person said it (a line of a todo: - [ ] Acheter du pain)"),
            ]),
            risk: .write,
            outputKeys: ["path", "originalBytes", "originalHash", "added", "reply"])
    }

    /// The approval shows the exact file and the exact text.
    func action(for arguments: ToolArguments) -> ToolAction? {
        guard case .string(let raw)? = arguments["path"] else { return nil }
        var content: String?
        if case .string(let text)? = arguments["text"] { content = text.trimmingCharacters(in: .newlines) }
        return ToolAction(kind: .modify, resources: [.file(resolve(raw))], reversible: true, content: content)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do {
            _ = try target(arguments)
            return nil
        } catch {
            if case .invalidInput(let reason) = error { return reason }
            if case .failed(let reason) = error { return reason }
            return "ajout impossible"
        }
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let (path, text) = try target(arguments)
        guard let original = FileManager.default.contents(atPath: path) else { throw ToolError.failed(loc("je ne peux pas lire \(display(path))")) }
        let addition = Data(Self.addition(text, after: original).utf8)
        try Task.checkCancellation()
        // O_NOFOLLOW: a file swapped for a link since the check is refused by the system itself.
        let descriptor = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ToolError.failed(errno == ELOOP ? loc("\(display(path)) est devenu un lien, je n'y touche pas") : loc("je ne peux pas écrire dans \(display(path))"))
        }
        defer { close(descriptor) }
        let written = addition.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == addition.count else { throw ToolError.failed(loc("l'ajout dans \(display(path)) a échoué")) }
        return ToolOutput(summary: "Added to \(display(path)).",
                          values: ["path": .string(path), "originalBytes": .number(Double(original.count)),
                                   "originalHash": .string(Self.hash(original)),
                                   "added": .string(String(decoding: addition, as: UTF8.self)),
                                   "reply": .string(loc("C'est ajouté à la fin de \(display(path))."))])
    }

    /// The beginning is what it was, and the end is what was added.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let path)? = output.values["path"], case .number(let count)? = output.values["originalBytes"],
              case .string(let hash)? = output.values["originalHash"], case .string(let added)? = output.values["added"] else {
            return loc("rien à vérifier")
        }
        guard let now = FileManager.default.contents(atPath: path) else { return loc("\(display(path)) n'existe plus") }
        let addedData = Data(added.utf8)
        guard now.count >= Int(count) + addedData.count else { return loc("\(display(path)) est plus court que prévu") }
        if Self.hash(now.prefix(Int(count))) != hash { return loc("le début de \(display(path)) a changé") }
        if !now.suffix(addedData.count).elementsEqual(addedData) { return loc("la fin de \(display(path)) ne contient pas le texte ajouté") }
        return nil
    }

    // MARK: - Checks

    /// The file and the text, or why not. Everything that can be known before writing.
    private func target(_ arguments: ToolArguments) throws(ToolError) -> (String, String) {
        guard case .string(let raw)? = arguments["path"], case .string(let rawText)? = arguments["text"] else {
            throw .invalidInput(loc("il me faut le fichier et le texte à ajouter"))
        }
        let text = rawText.trimmingCharacters(in: .newlines)
        guard text.nonEmptyTrimmed != nil else { throw .invalidInput(loc("le texte à ajouter est vide")) }
        guard text.count <= Self.maxCharacters else { throw .invalidInput(loc("le texte dépasse \(Self.maxCharacters) caractères")) }
        let path = resolve(raw)
        guard path.hasPrefix("/") else { throw .invalidInput(loc("je ne sais pas de quel fichier il s'agit")) }
        let created = Set(log.paths().map(Self.normalised))
        guard created.contains(Self.normalised(path)) else {
            throw .invalidInput(loc("je n'ajoute qu'aux fichiers que j'ai créés moi-même, et \(display(path)) n'en fait pas partie"))
        }
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
        let roots = allowedFolders.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        guard roots.contains(where: { RiskAssessor.path(folder, isInside: $0) }) else {
            throw .invalidInput(loc("\(display(path)) n'est plus dans Téléchargements, sur le Bureau ou dans Documents"))
        }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if errno == ENOENT { throw .invalidInput(loc("\(display(path)) n'existe plus à cet endroit")) }
            throw .failed(loc("macOS ne me laisse pas accéder à \(display(folder)). Autorise Yumi dans Réglages Système, Confidentialité et sécurité, Fichiers et dossiers"))
        }
        if (info.st_mode & S_IFMT) == S_IFLNK { throw .invalidInput(loc("\(display(path)) est un lien, je n'y touche pas")) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .invalidInput(loc("\(display(path)) n'est pas un fichier")) }
        guard info.st_size <= Self.maxFileBytes else { throw .invalidInput(loc("\(display(path)) est trop gros pour que j'y ajoute quelque chose")) }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw .failed(loc("macOS ne me laisse pas lire \(display(path)). Autorise Yumi dans Réglages Système, Confidentialité et sécurité, Fichiers et dossiers"))
        }
        guard String(data: data, encoding: .utf8) != nil else { throw .invalidInput(loc("\(display(path)) n'est pas un fichier texte")) }
        guard FileManager.default.isWritableFile(atPath: path) else { throw .invalidInput(loc("je n'ai pas le droit d'écrire dans \(display(path))")) }
        return (path, text)
    }

    /// What is written: the text on its own line, ending with a line break.
    static func addition(_ text: String, after original: Data) -> String {
        let separator = original.isEmpty || original.last == UInt8(ascii: "\n") ? "" : "\n"
        return separator + text + "\n"
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalised(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    // MARK: - Paths

    /// `~/x` from the home folder. A name alone is the created file of that name when there is
    /// exactly one, otherwise the one in Downloads.
    private func resolve(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.contains("/") {
            let named = log.paths().filter { ($0 as NSString).lastPathComponent == trimmed }
            if named.count == 1 { return named[0] }
            return ((home as NSString).appendingPathComponent("Downloads") as NSString).appendingPathComponent(trimmed)
        }
        return trimmed.hasPrefix("~/") ? home + trimmed.dropFirst() : trimmed
    }

    private func display(_ path: String) -> String {
        RiskAssessor.path(path, isInside: home) ? "~" + path.dropFirst(home.count) : path
    }
}
