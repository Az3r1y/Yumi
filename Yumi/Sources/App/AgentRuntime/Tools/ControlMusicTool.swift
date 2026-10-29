import Foundation

/// What can be asked of the music: play, pause, the next or the previous track.
enum MusicCommand: String, CaseIterable, Sendable {
    case play, pause, next, previous

    var goal: String {
        switch self {
        case .play: loc("Mettre la musique")
        case .pause: loc("Mettre la musique en pause")
        case .next: loc("Passer au morceau suivant")
        case .previous: loc("Revenir au morceau précédent")
        }
    }

    var reply: String {
        switch self {
        case .play: loc("C'est parti pour la musique.")
        case .pause: loc("Musique en pause.")
        case .next: loc("Morceau suivant.")
        case .previous: loc("Morceau précédent.")
        }
    }
}

/// The Music module, seen from the agent. Implemented by `ModuleBridge`.
protocol MusicControl: Sendable {
    /// nil when it was done, otherwise why not, in words for the person.
    func perform(_ command: MusicCommand) async -> String?
}

/// Plays, pauses or skips the music of the player the Music module follows, as its buttons do.
/// Nothing personal is read and nothing leaves the Mac: it runs without asking.
struct ControlMusicTool: Tool {
    var music: any MusicControl

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "control_music",
            name: loc("Control the music"),
            description: "Plays, pauses, or skips to the next or previous track in the music player the person uses.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "action", type: .string, required: true, description: "play, pause, next or previous"),
            ]),
            risk: .none,
            outputKeys: ["action", "reply"])
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do { _ = try command(arguments) } catch { return error.reason }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let command = try command(arguments)
        try Task.checkCancellation()
        if let problem = await music.perform(command) { throw ToolError.failed(problem) }
        return ToolOutput(summary: "Music: \(command.rawValue).",
                          values: ["action": .string(command.rawValue), "reply": .string(command.reply)])
    }

    private func command(_ arguments: ToolArguments) throws(ToolError) -> MusicCommand {
        guard case .string(let raw)? = arguments["action"], let command = MusicCommand(rawValue: raw.lowercased()) else {
            throw .invalidInput(loc("je sais mettre la musique, la mettre en pause, passer au suivant ou revenir au précédent"))
        }
        return command
    }
}
