import Foundation

/// Where the Focus module stands, as far as the agent needs it.
enum FocusStatus: Equatable, Sendable {
    /// The module is not selected: nothing would show the session.
    case off
    case idle
    /// A session is under way (working, on a break, or paused). `length` is the work phase.
    case busy(remaining: TimeInterval, length: TimeInterval, focusing: Bool)
}

/// The Focus module, seen from the agent. Implemented by `FocusModule`'s bridge.
protocol FocusControl: Sendable {
    func status() async -> FocusStatus
    /// Starts one work session of this length. False when something already runs.
    func start(minutes: Int) async -> Bool
}

/// Starts one session of the Focus module. Never stops nor replaces a session under way.
/// Nothing leaves the Mac and nothing personal is read: it runs without asking.
struct StartFocusTool: Tool {
    static let minutes = 5...180
    static let defaultMinutes = 25

    var focus: any FocusControl

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "start_focus",
            name: "Start a focus session",
            description: "Starts one focus session of the Focus module, 25 minutes unless the person says how long; never replaces a session already running.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "minutes", type: .number, required: false, description: "length of the session, \(Self.minutes.lowerBound) to \(Self.minutes.upperBound); omit for 25"),
            ]),
            risk: .none,
            outputKeys: ["minutes", "reply"])
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do { _ = try minutes(arguments) } catch { return error.reason }
        return busy(await focus.status())
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let minutes = try minutes(arguments)
        if let problem = busy(await focus.status()) { throw ToolError.failed(problem) }
        try Task.checkCancellation()
        guard await focus.start(minutes: minutes) else { throw ToolError.failed("le Focus n'a pas démarré") }
        return ToolOutput(summary: "Started a \(minutes)-minute focus session.",
                          values: ["minutes": .number(Double(minutes)),
                                   "reply": .string("C'est parti pour \(FrenchText.spokenMinutes(TimeInterval(minutes * 60))). Je me tais.")])
    }

    /// The module runs a work session of the length asked, just started.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .number(let asked)? = output.values["minutes"] else { return "aucune durée à vérifier" }
        guard case .busy(let remaining, let length, let focusing) = await focus.status(), focusing else {
            return "le Focus ne tourne pas"
        }
        if length != asked * 60 { return "le Focus dure \(Int(length / 60)) minutes, pas \(Int(asked))" }
        if remaining <= 0 || remaining > length { return "le Focus n'est pas au début de sa session" }
        return nil
    }

    // MARK: -

    private func minutes(_ arguments: ToolArguments) throws(ToolError) -> Int {
        guard let value = arguments["minutes"] else { return Self.defaultMinutes }
        guard case .number(let number) = value, number.rounded() == number, Self.minutes.contains(Int(number)) else {
            throw .invalidInput("une session dure entre \(Self.minutes.lowerBound) et \(Self.minutes.upperBound) minutes")
        }
        return Int(number)
    }

    private func busy(_ status: FocusStatus) -> String? {
        switch status {
        case .off: "le module Focus est coupé. Active-le dans mes réglages et redemande-moi"
        case .idle: nil
        case .busy(let remaining, _, _): "un Focus tourne déjà, encore \(FrenchText.spokenMinutes(remaining)). Je ne le remplace pas"
        }
    }
}

extension ToolError {
    /// The words for the person, whatever the case.
    var reason: String {
        switch self {
        case .invalidInput(let reason), .unavailable(let reason), .failed(let reason): reason
        }
    }
}
