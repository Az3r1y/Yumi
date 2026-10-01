import Foundation

/// Decides how the app ends (Contracts/AppLifecycle.swift). When the user quits, Yumi says
/// goodbye first: the end is put off, the island is told, and the app ends when the island says
/// it is done, or after a few seconds whatever happens. When the Mac itself is logging out,
/// restarting or shutting down, nothing is ever put off.
struct QuitSequence: Equatable, Sendable {
    /// The longest the goodbye may hold the app, in seconds.
    static let patience: TimeInterval = 6

    enum Answer: Equatable, Sendable {
        /// Let the app end at once.
        case endNow
        /// Hold the app, tell the island, and wait for `finish()`.
        case sayGoodbye
    }

    private enum Stage: Sendable { case running, sayingGoodbye, ending }
    private var stage = Stage.running

    var isSayingGoodbye: Bool { stage == .sayingGoodbye }

    /// The app is asked to end.
    /// - Parameter systemReason: the reason macOS gives with the quit request when the session is
    ///   ending (log out, restart, shut down); nil or 0 when the user simply quits the app.
    mutating func request(systemReason: UInt32?) -> Answer {
        guard stage == .running, (systemReason ?? 0) == 0 else {
            // The Mac is ending the session, the goodbye is over, or the user insists: no delay.
            stage = .ending
            return .endNow
        }
        stage = .sayingGoodbye
        return .sayGoodbye
    }

    /// The goodbye is over, or it has lasted long enough, or the Mac is powering off.
    /// Returns true the one time the app must now be ended.
    mutating func finish() -> Bool {
        guard stage == .sayingGoodbye else { return false }
        stage = .ending
        return true
    }
}
