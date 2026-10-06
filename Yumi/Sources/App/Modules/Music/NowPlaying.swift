import Foundation

/// The apps Yumi can follow. Both announce their track changes to the whole system,
/// so no permission and no polling is needed to know what is playing.
enum MusicPlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    var name: String { self == .music ? "Musique" : "Spotify" }

    /// Name of the distributed notification the app posts when its playback changes.
    var notificationName: String {
        self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged"
    }
}

struct NowPlaying: Equatable, Sendable {
    var player: MusicPlayer
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    /// Length of the track in seconds, when the player says it.
    var duration: TimeInterval? = nil
    /// Position in the track when this was reported, in seconds. Not every player says it.
    var position: TimeInterval? = nil

    /// True when `other` is the same track, whatever its state.
    func isSameTrack(as other: NowPlaying) -> Bool {
        player == other.player && title == other.title && artist == other.artist && album == other.album
    }
}

/// Where a track is, between two reports of its player: a position and the moment it was true.
struct PlaybackClock: Equatable, Sendable {
    var position: TimeInterval
    var since: Date
    var isRunning: Bool

    func position(at now: Date) -> TimeInterval {
        isRunning ? position + max(0, now.timeIntervalSince(since)) : position
    }

    /// The clock after the player reported `new`. A reported position is taken as it is; a new
    /// track starts at zero; a pause freezes the clock and a resume restarts it. nil when the
    /// position cannot be known (a track found already paused, or nothing playing).
    static func next(_ clock: PlaybackClock?, from old: NowPlaying?, to new: NowPlaying?, now: Date) -> PlaybackClock? {
        guard let new else { return nil }
        if let reported = new.position {
            return PlaybackClock(position: reported, since: now, isRunning: new.isPlaying)
        }
        guard let old, old.isSameTrack(as: new) else {
            return new.isPlaying ? PlaybackClock(position: 0, since: now, isRunning: true) : nil
        }
        guard let clock else { return nil }
        return PlaybackClock(position: clock.position(at: now), since: now, isRunning: new.isPlaying)
    }
}

/// What a player just announced.
enum PlayerUpdate: Equatable, Sendable {
    case track(NowPlaying)
    case stopped(MusicPlayer)
}

enum MusicSummary {
    /// Reads the dictionary a player posts with its notification.
    static func update(from userInfo: [AnyHashable: Any]?, player: MusicPlayer) -> PlayerUpdate {
        let state = (userInfo?["Player State"] as? String ?? "").lowercased()
        guard let title = userInfo?["Name"] as? String, !title.isEmpty, state == "playing" || state == "paused" else {
            return .stopped(player)
        }
        // Music gives "Total Time" and Spotify "Duration", both in milliseconds; only Spotify gives the position.
        let milliseconds = number(userInfo?["Total Time"]) ?? number(userInfo?["Duration"])
        return .track(NowPlaying(player: player, title: title,
                                 artist: userInfo?["Artist"] as? String ?? "",
                                 album: userInfo?["Album"] as? String ?? "",
                                 isPlaying: state == "playing",
                                 duration: milliseconds.flatMap { $0 > 0 ? $0 / 1000 : nil },
                                 position: number(userInfo?["Playback Position"])))
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        // AppleScript writes decimals the way the Mac's region does: "12,5" in French.
        if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    /// Reads the answer of the AppleScript query: title, artist, album, state, position in seconds
    /// and duration, separated by tabs. Music gives the duration in seconds, Spotify in milliseconds.
    static func update(fromScriptResult result: String, player: MusicPlayer) -> PlayerUpdate {
        let fields = result.components(separatedBy: "\t")
        guard fields.count >= 4 else { return .stopped(player) }
        var info: [AnyHashable: Any] = ["Name": fields[0], "Artist": fields[1], "Album": fields[2], "Player State": fields[3]]
        if fields.count >= 6 {
            info["Playback Position"] = fields[4]
            if let duration = number(fields[5]) { info["Duration"] = player == .music ? duration * 1000 : duration }
        }
        return update(from: info, player: player)
    }

    /// What is playing after an update. The player that is playing keeps the stage:
    /// another one pausing or stopping in the background does not replace it.
    static func apply(_ update: PlayerUpdate, to current: NowPlaying?) -> NowPlaying? {
        switch update {
        case .track(let track):
            if track.isPlaying { return track }
            if let current, current.isPlaying, current.player != track.player { return current }
            return track
        case .stopped(let player):
            return current?.player == player ? nil : current
        }
    }

    /// How long a paused track stays in the folded island, so it can be resumed from there.
    static let pausedLinger: TimeInterval = 5 * 60

    /// What the folded island shows: the track while it plays, and for a few minutes after a pause.
    /// - Parameter pausedFor: seconds since the track was paused, when it is.
    static func live(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval? = nil) -> ModuleLive? {
        guard let playing else { return nil }
        if !playing.isPlaying {
            guard let pausedFor, pausedFor < pausedLinger else { return nil }
        }
        let text = playing.artist.isEmpty ? playing.title : "\(playing.title) · \(playing.artist)"
        let controls = [
            playing.isPlaying
                ? ModuleControl(id: ModuleAction.primary.rawValue, symbol: "pause.fill", label: loc("Pause"))
                : ModuleControl(id: ModuleAction.primary.rawValue, symbol: "play.fill", label: loc("Lecture")),
            ModuleControl(id: ModuleAction.secondary.rawValue, symbol: "forward.fill", label: loc("Suivant")),
        ]
        return ModuleLive(text: text,
                          priority: playing.isPlaying ? ModuleLivePriority.activity : ModuleLivePriority.ambient,
                          controls: canControl ? controls : [])
    }

    /// - Parameters:
    ///   - canControl: false in builds that may not send commands to other apps.
    ///   - pausedFor: seconds since the track was paused, when it is.
    ///   - position: seconds into the track, when it is known.
    static func snapshot(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval? = nil,
                         position: TimeInterval? = nil) -> ModuleSnapshot {
        var snapshot = plainSnapshot(playing, canControl: canControl, pausedFor: pausedFor).withSymbols("music.note")
        if let duration = playing?.duration, duration > 0, let position {
            let at = min(duration, max(0, position))
            snapshot.progress = ModuleProgress(fraction: at / duration, leading: FrenchText.trackTime(at),
                                               trailing: FrenchText.trackTime(duration))
        }
        return snapshot
    }

    private static func plainSnapshot(_ playing: NowPlaying?, canControl: Bool, pausedFor: TimeInterval?) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "music", name: loc("Musique"), colorHex: "#F58AD9", status: "silence",
                                      title: loc("Pas de musique."), subtitle: loc("Lance un morceau, j'écoute avec toi."),
                                      primaryAction: loc("Ouvrir Musique"), secondaryAction: nil)
        guard let playing else { return snapshot }

        snapshot.status = playing.isPlaying ? "lecture" : "pause"
        snapshot.title = playing.title
        let credits = [playing.artist, playing.album].filter { !$0.isEmpty }
        snapshot.subtitle = credits.isEmpty ? playing.player.name : credits.joined(separator: ", ")
        if canControl {
            snapshot.primaryAction = playing.isPlaying ? "Pause" : "Lecture"
            snapshot.secondaryAction = "Suivant"
        } else {
            snapshot.primaryAction = "Ouvrir \(playing.player.name)"
        }
        snapshot.live = live(playing, canControl: canControl, pausedFor: pausedFor)
        return snapshot
    }
}
