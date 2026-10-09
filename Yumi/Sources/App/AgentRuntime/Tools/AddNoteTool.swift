import Foundation

/// The Notes app, seen from the agent. `ScriptedNotes` drives it with AppleScript.
protocol AppleNotesApp: Sendable {
    func add(title: String, body: String) throws
    func exists(title: String) -> Bool
}

/// "Note que…": one new note in the Notes app. Never changes nor removes a note; asked before,
/// checked after.
struct AddNoteTool: Tool {
    static let maxBody = 20_000
    var notes: any AppleNotesApp

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "add_note",
            name: loc("Create a note"),
            description: "Creates one new note in the Apple Notes app with a short title and the text the person gives; use it when the person asks to note or write down something in Notes.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "title", type: .string, required: true, description: "a short title for the note"),
                .init(name: "body", type: .string, required: true, description: "the text of the note, as the person said it"),
            ]),
            risk: .write,
            outputKeys: ["title", "reply"])
    }

    func action(for arguments: ToolArguments) -> ToolAction? {
        guard case .string(let raw)? = arguments["title"], let title = raw.nonEmptyTrimmed else { return nil }
        var body: String?
        if case .string(let text)? = arguments["body"] { body = text }
        return ToolAction(kind: .create, resources: [ResourceRef(.unknown, loc("la note « \(title) »"))], reversible: true,
                          content: body, headline: loc("Je dois créer la note « \(title) » dans Notes."))
    }

    func check(_ arguments: ToolArguments) async -> String? {
        guard Feature.isOn(.appleNotes) else { return loc("Les notes dans Notes sont coupées dans Réglages › Fonctions") }
        do { _ = try fields(arguments) } catch { return error.reason }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        if let refused = await check(arguments) { throw ToolError.invalidInput(refused) }
        let (title, body) = try fields(arguments)
        try Task.checkCancellation()
        do {
            try notes.add(title: title, body: body)
        } catch {
            throw ToolError.failed(loc("Notes n'a pas créé la note : \(error.localizedDescription)"))
        }
        return ToolOutput(summary: "Created the note \(title).",
                          values: ["title": .string(title), "reply": .string(loc("C'est noté dans Notes : « \(title) »."))])
    }

    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let title)? = output.values["title"] else { return loc("aucune note à vérifier") }
        return notes.exists(title: title) ? nil : loc("la note « \(title) » n'est pas dans Notes")
    }

    private func fields(_ arguments: ToolArguments) throws(ToolError) -> (String, String) {
        guard case .string(let rawTitle)? = arguments["title"], let title = rawTitle.nonEmptyTrimmed,
              case .string(let body)? = arguments["body"] else { throw .invalidInput(loc("il manque le titre ou le texte de la note")) }
        guard body.count <= Self.maxBody else { throw .invalidInput(loc("le texte est trop long pour une note")) }
        return (String(title.prefix(120)), body)
    }
}

/// The real Notes app, through AppleScript. Texts go in as AppleScript strings, escaped: never
/// as code.
struct ScriptedNotes: AppleNotesApp {
    enum Failure: Error, LocalizedError {
        case script(String)
        var errorDescription: String? { if case .script(let why) = self { why } else { nil } }
    }

    func add(title: String, body: String) throws {
        let html = "<h1>\(Self.html(title))</h1>" + body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "<div>\(Self.html(String($0)))</div>" }.joined()
        try run("tell application \"Notes\" to make new note with properties {body:\(Self.quoted(html))}")
    }

    func exists(title: String) -> Bool {
        (try? run("tell application \"Notes\" to return (count of (notes whose name is \(Self.quoted(title)))) > 0")) == "true"
    }

    @discardableResult
    private func run(_ source: String) throws -> String {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { throw Failure.script(error[NSAppleScript.errorMessage] as? String ?? "AppleScript") }
        return result?.stringValue ?? ""
    }

    /// An AppleScript string literal: backslashes and quotes escaped.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func html(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
