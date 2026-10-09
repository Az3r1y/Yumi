import Foundation

/// The person's Shortcuts app, seen from the agent. `SystemShortcuts` asks `/usr/bin/shortcuts`.
protocol ShortcutsLibrary: Sendable {
    /// The names of the person's shortcuts; nil when they cannot be read.
    func names() async -> [String]?
    /// Runs one and waits for its end. Throws, with the reason, when it fails.
    func run(_ name: String) async throws
}

/// Runs one of the person's shortcuts, by its name. A shortcut can do anything it was built
/// for (send a message, delete a file…), and Yumi cannot see inside it: the person is asked
/// every time, and no answer is remembered.
struct RunShortcutTool: Tool {
    var library: any ShortcutsLibrary

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "run_shortcut",
            name: loc("Run a shortcut"),
            description: "Runs one of the person's shortcuts from the Shortcuts app, by its name; use it only when the person names a shortcut to run.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "name", type: .string, required: true, description: "the name of the shortcut, as the person says it"),
            ]),
            risk: .write,
            outputKeys: ["name", "reply"])
    }

    func action(for arguments: ToolArguments) -> ToolAction? {
        guard case .string(let raw)? = arguments["name"], let name = raw.nonEmptyTrimmed else { return nil }
        // What it does is the shortcut's business: an unknown resource that cannot be undone,
        // asked every time
        return ToolAction(kind: .other, resources: [ResourceRef(.unknown, loc("le raccourci « \(name) »"))], reversible: false)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do { _ = try await resolve(arguments) } catch { return error.reason }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let name = try await resolve(arguments)
        try Task.checkCancellation()
        do {
            try await library.run(name)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ToolError.failed(loc("le raccourci « \(name) » s'est arrêté : \((error as? ToolError)?.reason ?? error.localizedDescription)"))
        }
        return ToolOutput(summary: "Ran the shortcut \(name).",
                          values: ["name": .string(name), "reply": .string(loc("C'est fait, j'ai lancé « \(name) ».")) ])
    }

    // MARK: -

    /// The shortcut's own name, found without case nor surrounding spaces, or why not.
    private func resolve(_ arguments: ToolArguments) async throws(ToolError) -> String {
        guard case .string(let raw)? = arguments["name"], let asked = raw.nonEmptyTrimmed else {
            throw .invalidInput(loc("il manque le nom du raccourci"))
        }
        guard let names = await library.names() else { throw .unavailable(loc("je n'arrive pas à lire tes raccourcis")) }
        if let name = names.first(where: { $0.compare(asked, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return name
        }
        let known = names.prefix(8).map { "« \($0) »" }.joined(separator: ", ")
        throw .invalidInput(names.isEmpty ? loc("tu n'as aucun raccourci dans l'app Raccourcis")
                                          : loc("je ne trouve pas de raccourci « \(asked) ». Tu as : \(known)"))
    }
}

/// The real Shortcuts app, through its command line tool.
struct SystemShortcuts: ShortcutsLibrary {
    static let tool = "/usr/bin/shortcuts"

    func names() async -> [String]? {
        guard let output = try? await Self.launch(["list"]) else { return nil }
        return output.split(separator: "\n").compactMap { String($0).nonEmptyTrimmed }
    }

    func run(_ name: String) async throws {
        _ = try await Self.launch(["run", name])
    }

    /// Runs the tool without a shell (the name is one argument, never a command line) and
    /// returns what it printed. Cancelling the task stops it.
    private static func launch(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // One pipe for both outputs, read to its end while the tool runs: a full pipe would
        // leave it waiting forever
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try await Task.detached {
                try process.run()
                let printed = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationReason == .uncaughtSignal { throw CancellationError() }
                guard process.terminationStatus == 0 else {
                    throw ToolError.failed(printed.nonEmptyTrimmed ?? "code \(process.terminationStatus)")
                }
                return printed
            }.value
        } onCancel: {
            process.terminate()
        }
    }
}
