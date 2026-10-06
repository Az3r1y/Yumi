import Foundation

/// Something that happened on the Mac, as the Context Engine records it in its history.
struct ContextEvent: Identifiable, Equatable, Codable, Sendable {
    /// Increases with every event of one run of the engine.
    let id: Int
    let date: Date
    let kind: Kind

    enum Kind: Equatable, Codable, Sendable {
        /// The person is at the Mac: the engine started, the Mac woke up, the screen was unlocked.
        case sessionStarted
        /// The person left: sleep, lock, screens off, the engine stopped. `duration` in seconds.
        case sessionEnded(duration: TimeInterval)
        /// Another application came to the front.
        case applicationChanged(from: ApplicationContext?, to: ApplicationContext)
        /// The focused window changed, or its title did. nil when there is none, or it cannot be read.
        case windowChanged(from: WindowContext?, to: WindowContext?)
        case applicationLaunched(ApplicationContext)
        case applicationQuit(ApplicationContext)
        case system(ContextSystemSignal)
        /// A permission the engine depends on was granted or withdrawn.
        case permissionChanged(accessibility: ContextPermissionStatus)
        /// A future provider (screen, clipboard, files…) has something new.
        case facetChanged(ContextFacet.Kind)
    }

    /// One word for the debug panel and the traces.
    var name: String {
        switch kind {
        case .sessionStarted: "sessionStarted"
        case .sessionEnded: "sessionEnded"
        case .applicationChanged: "applicationChanged"
        case .windowChanged: "windowChanged"
        case .applicationLaunched: "applicationLaunched"
        case .applicationQuit: "applicationQuit"
        case .system: "system"
        case .permissionChanged: "permissionChanged"
        case .facetChanged: "facetChanged"
        }
    }

    /// A line for the debug panel.
    var summary: String {
        switch kind {
        case .sessionStarted: loc("Session started")
        case .sessionEnded(let duration): loc("Session ended after \(ContextFormat.duration(duration))")
        case .applicationChanged(_, let to): "→ \(to.name)"
        case .windowChanged(_, let to): loc("Window: \(to.map { $0.title.isEmpty ? "untitled" : $0.title } ?? "none")")
        case .applicationLaunched(let app): "Launched \(app.name)"
        case .applicationQuit(let app): "Quit \(app.name)"
        case .system(let signal): signal.rawValue
        case .permissionChanged(let status): loc("Accessibility \(status.rawValue)")
        case .facetChanged(let kind): "\(kind.rawValue) changed"
        }
    }
}

/// What the system says about the person's presence. Several macOS notifications can mean the
/// same thing; each one is kept apart so that the history stays faithful.
enum ContextSystemSignal: String, Codable, Sendable, CaseIterable {
    case willSleep, didWake
    case screensDidSleep, screensDidWake
    case screenLocked, screenUnlocked
    /// Fast user switching: another account took the screen, or this one got it back.
    case sessionResigned, sessionResumed

    /// The person is (probably) no longer in front of the Mac.
    var isDeparture: Bool {
        switch self {
        case .willSleep, .screensDidSleep, .screenLocked, .sessionResigned: true
        case .didWake, .screensDidWake, .screenUnlocked, .sessionResumed: false
        }
    }
}

/// Messages of the engine. Every change is told as an event, then as the new snapshot.
enum ContextMessage: Sendable {
    /// applicationChanged, windowChanged, sessionStarted, sessionEnded, and the system events.
    case event(ContextEvent)
    /// The snapshot after one or more events, or after a change of Yumi's presence.
    case contextUpdated(ContextSnapshot)
}

enum ContextFormat {
    /// "18m 32s", "2h 05m", "12s".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        if hours > 0 { return loc("\(hours)h \(String(format: "%02d", minutes))m") }
        if minutes > 0 { return loc("\(minutes)m \(String(format: "%02d", rest))s") }
        return "\(rest)s"
    }
}
