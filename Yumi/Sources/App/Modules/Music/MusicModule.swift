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

    /// Where the track is, kept between two reports of the player.
    private var clock: PlaybackClock?
    private var ticking: Task<Void, Never>?

    var snapshot: ModuleSnapshot {
        let now = Date()
        return MusicSummary.snapshot(playing, canControl: Self.canControl,
                                     pausedFor: pausedAt.map { now.timeIntervalSince($0) },
                                     position: clock?.position(at: now))
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        for player in MusicPlayer.allCases {
            guard let name = player.notificationName else { continue }
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] note in
                let update = MusicSummary.update(from: note.userInfo, player: player)
                MainActor.assumeIsolated {
                    self?.receive(update)
                    // Music does not say where the track is: ask, if it is already allowed.
                    if player == .music, case .track(let track) = update, track.isPlaying { self?.askWhatIsPlaying(player) }
                }
            }
            observers.append(observer)
            askWhatIsPlaying(player)
        }
        #if !APPSTORE
        watchTitles()
        #endif
    }

    // MARK: Players read from their window

    private var titleWatch: Task<Void, Never>?
    /// What the window titles showed at the last look, by player.
    private var titled: [MusicPlayer: NowPlaying] = [:]

    #if !APPSTORE
    /// Every three seconds, the titles of the windows of Deezer, YouTube Music and the browsers:
    /// read through Accessibility (the permission Yumi already has for window titles), only
    /// while the module is selected.
    private func watchTitles() {
        titleWatch?.cancel()
        titleWatch = Task { [weak self] in
            while !Task.isCancelled {
                self?.lookAtTitles()
                try? await Task.sleep(for: .seconds(3), tolerance: .seconds(1))
            }
        }
    }

    private func lookAtTitles() {
        guard AXIsProcessTrusted() else { return }
        var found: [MusicPlayer: NowPlaying] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName ?? ""
            let id = app.bundleIdentifier ?? ""
            let browser = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox", "company.thebrowser.Browser",
                           "com.apple.Safari", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"].contains(id)
            guard browser || id == MusicPlayer.deezer.rawValue || id.hasPrefix("com.google.Chrome.app.")
                    || name.localizedCaseInsensitiveContains("Deezer") || name.localizedCaseInsensitiveContains("YouTube Music") else { continue }
            for title in Self.windowTitles(of: app.processIdentifier) {
                guard let track = MusicTitles.parse(title, appName: name), found[track.player] == nil else { continue }
                // A title player does not say whether it is paused: the last button pressed decides
                let wasPaused = titled[track.player].map { !$0.isPlaying && $0.title == track.title } ?? false
                found[track.player] = NowPlaying(player: track.player, title: track.title, artist: track.artist, album: "", isPlaying: !wasPaused)
            }
        }
        for player in Set(titled.keys).subtracting(found.keys) { receive(.stopped(player)) }
        for (_, track) in found where titled[track.player] != track { receive(.track(track)) }
        titled = found
    }

    private static func windowTitles(of pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.prefix(12).compactMap { window in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
            return title as? String
        }
    }

    /// The Mac's media keys: whatever app plays (a browser tab, Deezer) receives them.
    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                                 windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    #endif

    func stop() {
        onChange = nil
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers = []
        titleWatch?.cancel()
        titleWatch = nil
        titled = [:]
        playing = nil
        pausedAt = nil
        lingering?.cancel()
        lingering = nil
        clock = nil
        ticking?.cancel()
        ticking = nil
    }

    private func receive(_ update: PlayerUpdate) {
        let next = MusicSummary.apply(update, to: playing)
        guard next != playing, onChange != nil else { return }
        let wasPaused = playing.map { !$0.isPlaying } ?? false
        clock = PlaybackClock.next(clock, from: playing, to: next, now: Date())
        playing = next
        notePause(wasPaused: wasPaused)
        syncTicking()
        onChange?()
    }

    /// The playback bar moves every second, but only while a track with a known position plays.
    private func syncTicking() {
        if clock?.isRunning == true, playing?.duration != nil, onChange != nil {
            guard ticking == nil else { return }
            ticking = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    self?.onChange?()
                }
            }
        } else {
            ticking?.cancel()
            ticking = nil
        }
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
        guard playing.player.isScriptable else {
            // NX_KEYTYPE_PLAY 16, NEXT 17, PREVIOUS 18
            Self.mediaKey(action == .primary ? 16 : action == .secondary ? 17 : 18)
            if action == .primary {
                var toggled = playing
                toggled.isPlaying.toggle()
                titled[playing.player] = toggled
                receive(.track(toggled))
            }
            return
        }
        let command = action == .primary ? "playpause" : action == .secondary ? "next track" : "previous track"
        PlayerScripting.run("tell application id \"\(playing.player.rawValue)\" to \(command)", on: playing.player, askingFirst: true) { result in
            // Refused: the only way back is the Automation pane of System Settings.
            if case .failure(.notAllowed) = result {
                Task { @MainActor in NSWorkspace.shared.open(PrivacySettings.automation) }
            }
        }
        #endif
    }

    /// What the agent asks (`control_music`), with the module's own buttons. nil when done,
    /// otherwise why not. With nothing playing, « play » opens the player.
    func control(_ command: MusicCommand) -> String? {
        switch command {
        case .play:
            if playing?.isPlaying == true { return nil }
            perform(.primary)
        case .pause:
            guard playing?.isPlaying == true else { return loc("rien ne joue en ce moment") }
            perform(.primary)
        case .next, .previous:
            guard playing != nil else { return loc("rien ne joue en ce moment") }
            perform(command == .next ? .secondary : .previous)
        }
        return nil
    }

    private func open(_ player: MusicPlayer) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else {
            if let url = player.webURL { NSWorkspace.shared.open(url) }
            return
        }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    // MARK: Initial state

    /// A track already playing when the module starts was announced before Yumi listened.
    /// Ask the player, but only if it is running and the user already allowed Yumi to talk to it:
    /// this never opens an app and never shows a permission dialog.
    private func askWhatIsPlaying(_ player: MusicPlayer) {
        #if !APPSTORE
        guard player.isScriptable else { return }
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == player.rawValue }) else { return }
        let script = """
        tell application id "\(player.rawValue)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player state as text) & tab & (player position as text) & tab & (duration of t as text)
        end tell
        """
        PlayerScripting.run(script, on: player, askingFirst: false) { [weak self] result in
            guard case .success(let text) = result else { return }
            let update = MusicSummary.update(fromScriptResult: text, player: player)
            Task { @MainActor in
                // Only a track that is playing is news: a stopped player says nothing, and a track
                // found paused was paused at an unknown time, not just now.
                if case .track(let track) = update, track.isPlaying { self?.receive(update) }
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
        let allowedKey = "playerAllowed.\(player.rawValue)"
        // The system can tell whether the permission was granted (AEDeterminePermissionToAutomateTarget),
        // but that call sometimes never returns, and it held every later pause and next behind it
        // on this queue. Yumi remembers instead that a command to this player went through.
        if !askingFirst, !UserDefaults.standard.bool(forKey: allowedKey) {
            completion(.failure(.notAllowed))
            return
        }
        queue.async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int
                if code == notAuthorized { UserDefaults.standard.set(false, forKey: allowedKey) }
                completion(.failure(code == notAuthorized ? .notAllowed : .failed))
            } else {
                UserDefaults.standard.set(true, forKey: allowedKey)
                completion(.success(output?.stringValue ?? ""))
            }
        }
    }
}
#endif
