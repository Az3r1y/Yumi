import AppKit

/// The track playing in Music or Spotify. Track changes are pushed by the players; the module
/// only talks to them (AppleScript) when the user presses a button.
@MainActor
final class MusicModule: YumiModule {
    let id = "music"

    #if APPSTORE
    /// The sandbox does not let the app send commands to the players.
    private static let canControl = false
    #else
    private static let canControl = true
    #endif

    private var playing: NowPlaying?
    private var onChange: (@MainActor () -> Void)?
    private var observers: [NSObjectProtocol] = []

    /// When the current track was paused; nil while it plays.
    private var pausedAt: Date?
    private var lingering: Task<Void, Never>?

    var snapshot: ModuleSnapshot {
        MusicSummary.snapshot(playing, canControl: Self.canControl,
                              pausedFor: pausedAt.map { Date().timeIntervalSince($0) })
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        for player in MusicPlayer.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(player.notificationName), object: nil, queue: .main
            ) { [weak self] note in
                let update = MusicSummary.update(from: note.userInfo, player: player)
                MainActor.assumeIsolated { self?.receive(update) }
            }
            observers.append(observer)
            askWhatIsPlaying(player)
        }
    }

    func stop() {
        onChange = nil
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers = []
        playing = nil
        pausedAt = nil
        lingering?.cancel()
        lingering = nil
    }

    private func receive(_ update: PlayerUpdate) {
        let next = MusicSummary.apply(update, to: playing)
        guard next != playing, onChange != nil else { return }
        let wasPaused = playing.map { !$0.isPlaying } ?? false
        playing = next
        notePause(wasPaused: wasPaused)
        onChange?()
    }

    /// A paused track leaves the folded island after a while: report again when that moment comes.
    private func notePause(wasPaused: Bool) {
        guard let playing, !playing.isPlaying else {
            pausedAt = nil
            lingering?.cancel()
            lingering = nil
            return
        }
        // Still paused (the player only refreshed its details): the clock keeps running.
        if wasPaused, pausedAt != nil { return }
        pausedAt = Date()
        lingering?.cancel()
        lingering = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MusicSummary.pausedLinger + 1))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        guard let playing, Self.canControl else {
            open(playing?.player ?? .music)
            return
        }
        #if !APPSTORE
        let command = action == .primary ? "playpause" : "next track"
        PlayerScripting.run("tell application id \"\(playing.player.rawValue)\" to \(command)", on: playing.player, askingFirst: true) { result in
            // Refused: the only way back is the Automation pane of System Settings.
            if case .failure(.notAllowed) = result {
                Task { @MainActor in NSWorkspace.shared.open(PrivacySettings.automation) }
            }
        }
        #endif
    }

    private func open(_ player: MusicPlayer) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    // MARK: Initial state

    /// A track already playing when the module starts was announced before Yumi listened.
    /// Ask the player, but only if it is running and the user already allowed Yumi to talk to it:
    /// this never opens an app and never shows a permission dialog.
    private func askWhatIsPlaying(_ player: MusicPlayer) {
        #if !APPSTORE
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == player.rawValue }) else { return }
        let script = """
        tell application id "\(player.rawValue)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player state as text)
        end tell
        """
        PlayerScripting.run(script, on: player, askingFirst: false) { [weak self] result in
            guard case .success(let text) = result else { return }
            let update = MusicSummary.update(fromScriptResult: text, player: player)
            Task { @MainActor in
                // A stopped player says nothing new; do not erase what a notification already told.
                if case .track = update { self?.receive(update) }
            }
        }
        #endif
    }
}

#if !APPSTORE
/// Sends AppleScript to a player, off the main thread: the first command can wait on a permission dialog.
private enum PlayerScripting {
    enum Failure: Error { case notAllowed, failed }

    private static let queue = DispatchQueue(label: "\(AppIdentity.notificationPrefix).player-scripting")
    /// AppleScript error for a refused Automation permission.
    private static let notAuthorized = -1743

    /// - Parameter askingFirst: false to give up silently when the permission was never granted,
    ///   instead of showing the system dialog.
    static func run(_ source: String, on player: MusicPlayer, askingFirst: Bool,
                    completion: @escaping @Sendable (Result<String, Failure>) -> Void) {
        queue.async {
            if !askingFirst, !isAlreadyAllowed(player) {
                completion(.failure(.notAllowed))
                return
            }
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int
                completion(.failure(code == notAuthorized ? .notAllowed : .failed))
            } else {
                completion(.success(output?.stringValue ?? ""))
            }
        }
    }

    /// True when the user already allowed Yumi to control the player.
    private static func isAlreadyAllowed(_ player: MusicPlayer) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr
    }
}
#endif
