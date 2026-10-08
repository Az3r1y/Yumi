import Foundation

/// Filming mode: `YUMI_STUDIO=1` shows Yumi without anything personal. Nothing real starts,
/// nothing is read from or written to Yumi's folder or the Keychain, and no permission can be
/// asked: `AppState` is left entirely to the island. Available in every build, Release included.
enum StudioMode {
    static let variable = "YUMI_STUDIO"

    /// True for this run of the app. Read once.
    static let isOn = isOn(in: ProcessInfo.processInfo.environment)

    /// Any value turns it on, except an empty one, "0", "false" and "no".
    static func isOn(in environment: [String: String]) -> Bool {
        guard let value = environment[variable]?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return !["", "0", "false", "no"].contains(value)
    }
}

/// What the app starts at launch. Everything in an ordinary run, nothing while filming.
struct LaunchPlan: Equatable, Sendable {
    /// The socket of the Claude Code hooks, and the hook script written in Yumi's folder.
    var hookServer: Bool
    /// The modules: calendar, reminders, location, music, GitHub, weather.
    var modules: Bool
    /// The memory file.
    var memory: Bool
    /// The remarks Yumi makes on his own.
    var initiative: Bool
    /// The chat, through Claude Code or the API.
    var chat: Bool
    /// The secrets of the Keychain.
    var keychain: Bool
    /// The Context Engine: which application and window are in front.
    var context: Bool

    init(studio: Bool) {
        let real = !studio
        hookServer = real
        modules = real
        memory = real
        initiative = real
        chat = real
        keychain = real
        context = real
    }

    /// The plan of this run.
    static let current = LaunchPlan(studio: StudioMode.isOn)

    /// True when nothing at all starts.
    var startsNothing: Bool {
        !(hookServer || modules || memory || initiative || chat || keychain || context)
    }
}

/// What the filming mode plays on demand, without a real event: a key while filming, or the
/// right-click menu. Nothing reaches Claude Code, GitHub or the initiative engine.
enum StudioCue: String, CaseIterable, Sendable {
    /// A permission asked by Claude, with buttons that answer nothing real.
    case approval
    /// The remark of a long stretch of work: "Deux heures d'affilée. Une pause ?".
    case breakRemark
    /// A GitHub scene, a different one at each press.
    case githubScene

    /// A, P and G (key codes of the US layout's positions).
    var keyCode: UInt16 {
        switch self {
        case .approval:    return 0
        case .breakRemark: return 35
        case .githubScene: return 5
        }
    }

    var keyEquivalent: String {
        switch self {
        case .approval:    return "a"
        case .breakRemark: return "p"
        case .githubScene: return "g"
        }
    }

    var title: String {
        switch self {
        case .approval:    return loc("Validation factice")
        case .breakRemark: return loc("Remarque : une pause ?")
        case .githubScene: return loc("Scène GitHub")
        }
    }

    static func forKey(_ code: UInt16) -> StudioCue? { allCases.first { $0.keyCode == code } }
}

/// The example data of the cues.
enum StudioFakes {
    static let approvalID = "studio-approval"

    static let approvalTool = "Bash"
    static let approvalCommand = "git push --force main"

    /// True for the studio's own approval: its buttons are answered here, not by the hooks.
    static func isFake(requestID: String?) -> Bool { requestID == approvalID }

    /// Whether Yumi celebrates once the fake approval is answered (allowed), or goes back
    /// to rest (refused).
    static func celebrates(after decision: String) -> Bool { decision == "allow" || decision == "always" }

    /// The initiative's own words for two hours in a row (its first wording). The id starts
    /// with "studio", which the filming mode lets through.
    static func breakRemark(name: String?, now: Date = .now) -> YumiRemark {
        let around = Surroundings(now: now, name: name)
        let variant = InitiativePhrases.variants(for: .longStretch(hours: 2), around).first
        return YumiRemark(id: "studio-stretch-\(now.timeIntervalSince1970)", text: variant?.text ?? "",
                          mood: variant?.mood ?? .worried, action: variant?.action?.label, duration: 8)
    }

    static let scenes: [YumiScene] = [.star, .merge, .fork, .release, .follower, .pullRequest]

    /// The scene after `last`, from the first again past the end.
    static func scene(after last: YumiScene?) -> YumiScene {
        guard let last, let index = scenes.firstIndex(of: last) else { return scenes[0] }
        return scenes[(index + 1) % scenes.count]
    }
}
