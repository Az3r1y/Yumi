import Testing
import Foundation

@Suite struct MusicSummaryTests {
    private let lueur = NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "Premières heures", isPlaying: true)

    @Test func readsWhatAPlayerAnnounces() {
        let info: [AnyHashable: Any] = ["Name": "Lueur", "Artist": "Halo Nord", "Album": "Premières heures", "Player State": "Playing"]
        #expect(MusicSummary.update(from: info, player: .music) == .track(lueur))
        #expect(MusicSummary.update(from: ["Player State": "Stopped"], player: .music) == .stopped(.music))
        #expect(MusicSummary.update(from: ["Player State": "Playing"], player: .spotify) == .stopped(.spotify))
        #expect(MusicSummary.update(from: nil, player: .music) == .stopped(.music))
    }

    @Test func readsTheScriptAnswer() {
        #expect(MusicSummary.update(fromScriptResult: "Lueur\tHalo Nord\tPremières heures\tplaying", player: .music) == .track(lueur))
        #expect(MusicSummary.update(fromScriptResult: "", player: .music) == .stopped(.music))
    }

    @Test func thePlayingPlayerKeepsTheStage() {
        var paused = lueur
        paused.isPlaying = false
        let other = NowPlaying(player: .spotify, title: "Autre", artist: "", album: "", isPlaying: false)

        #expect(MusicSummary.apply(.track(lueur), to: nil) == lueur)
        #expect(MusicSummary.apply(.track(paused), to: lueur) == paused)
        #expect(MusicSummary.apply(.track(other), to: lueur) == lueur)
        #expect(MusicSummary.apply(.stopped(.spotify), to: lueur) == lueur)
        #expect(MusicSummary.apply(.stopped(.music), to: lueur) == nil)
        #expect(MusicSummary.apply(.track(other), to: paused) == other)
    }

    @Test func snapshots() {
        let silent = MusicSummary.snapshot(nil, canControl: true)
        #expect(silent.status == "silence")
        #expect(silent.primaryAction == "Ouvrir Musique")
        #expect(silent.secondaryAction == nil)

        let playing = MusicSummary.snapshot(lueur, canControl: true)
        #expect(playing.id == "music")
        #expect(playing.status == "lecture")
        #expect(playing.title == "Lueur")
        #expect(playing.subtitle == "Halo Nord, Premières heures")
        #expect(playing.primaryAction == "Pause")
        #expect(playing.secondaryAction == "Suivant")

        var paused = lueur
        paused.isPlaying = false
        paused.album = ""
        #expect(MusicSummary.snapshot(paused, canControl: true).primaryAction == "Lecture")
        #expect(MusicSummary.snapshot(paused, canControl: true).subtitle == "Halo Nord")

        let sandboxed = MusicSummary.snapshot(lueur, canControl: false)
        #expect(sandboxed.primaryAction == "Ouvrir Musique")
        #expect(sandboxed.secondaryAction == nil)
    }
}
