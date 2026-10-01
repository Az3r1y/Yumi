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
        return .track(NowPlaying(player: player, title: title,
                                 artist: userInfo?["Artist"] as? String ?? "",
                                 album: userInfo?["Album"] as? String ?? "",
                                 isPlaying: state == "playing"))
    }

    /// Reads the answer of the AppleScript query: title, artist, album and state separated by tabs.
    static func update(fromScriptResult result: String, player: MusicPlayer) -> PlayerUpdate {
        let fields = result.components(separatedBy: "\t")
        guard fields.count == 4 else { return .stopped(player) }
        return update(from: ["Name": fields[0], "Artist": fields[1], "Album": fields[2], "Player State": fields[3]],
                      player: player)
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

    /// - Parameter canControl: false in builds that may not send commands to other apps.
    static func snapshot(_ playing: NowPlaying?, canControl: Bool) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "music", name: "Musique", colorHex: "#F58AD9", status: "silence",
                                      title: "Rien en lecture", subtitle: "Lance Musique ou Spotify",
                                      primaryAction: "Ouvrir Musique", secondaryAction: nil)
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
        return snapshot
    }
}
