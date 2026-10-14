import Testing
import Foundation

@Suite struct BrowserMediaTitlesTests {
    @Test func readsAYouTubeVideoInAnyBrowser() {
        let chrome = MusicTitles.parse("Halo Nord - Lueur (clip officiel) - YouTube - Google Chrome")
        #expect(chrome?.player == .youtube && chrome?.title == "Halo Nord - Lueur (clip officiel)" && chrome?.artist == "")
        // Arc puts no browser name in its window titles, and YouTube counts the notifications in front
        let arc = MusicTitles.parse("(3) Halo Nord - Lueur - YouTube")
        #expect(arc?.player == .youtube && arc?.title == "Halo Nord - Lueur")
        let firefox = MusicTitles.parse("(12+) Lueur - YouTube — Mozilla Firefox")
        #expect(firefox?.title == "Lueur")
    }

    @Test func youTubeMusicIsNotYouTube() {
        let music = MusicTitles.parse("Lueur • Halo Nord - YouTube Music")
        #expect(music?.player == .youtubeMusic && music?.artist == "Halo Nord")
    }

    @Test func readsSoundCloudTwitchAndVimeo() {
        let soundcloud = MusicTitles.parse("Stream Lueur by Halo Nord | Listen online for free on SoundCloud - Safari")
        #expect(soundcloud?.player == .soundcloud && soundcloud?.title == "Lueur" && soundcloud?.artist == "Halo Nord")
        let twitch = MusicTitles.parse("halonord - Twitch")
        #expect(twitch?.player == .twitch && twitch?.title == "halonord")
        let vimeo = MusicTitles.parse("Premières heures on Vimeo - Brave")
        #expect(vimeo?.player == .vimeo && vimeo?.title == "Premières heures")
    }

    @Test func ignoresTheSitesThemselves() {
        #expect(MusicTitles.parse("YouTube - Google Chrome") == nil)
        #expect(MusicTitles.parse("(2) YouTube") == nil)
        #expect(MusicTitles.parse("Abonnements - YouTube") == nil)
        #expect(MusicTitles.parse("Twitch") == nil)
        #expect(MusicTitles.parse("Lueur - Google Docs - Google Chrome") == nil)
        #expect(!MusicPlayer.youtube.isScriptable && MusicPlayer.youtube.notificationName == nil)
        #expect(MusicPlayer.youtube.webURL != nil)
    }
}

@Suite struct TitlePlaybackTests {
    @Test func findsTheSoundOfABrowserInItsHelpers() {
        let audible: Set<String> = ["company.thebrowser.browser.helper", "com.apple.music"]
        #expect(TitlePlayback.isAudible("company.thebrowser.Browser", among: audible))
        #expect(TitlePlayback.isAudible("com.apple.Music", among: audible))
        #expect(!TitlePlayback.isAudible("com.google.Chrome", among: audible))
        #expect(TitlePlayback.isAudible("com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod", among: ["com.google.chrome.helper"]))
        #expect(TitlePlayback.isAudible("com.apple.Safari", among: ["com.apple.webkit.gpu"]))
        #expect(TitlePlayback.isAudible("org.mozilla.firefox", among: ["org.mozilla.plugincontainer"]))
        // A prefix that is not a helper does not count
        #expect(!TitlePlayback.isAudible("com.brave.Browser", among: ["com.brave.browserextra"]))
        #expect(!TitlePlayback.isAudible("com.google.Chrome", among: []))
    }

    @Test func aPageNeverHeardIsNotATrack() {
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: nil, audible: false) == nil)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: nil, audible: true) == true)
    }

    @Test func aTrackHeardThenSilentIsPaused() {
        let lueur = NowPlaying(player: .youtube, title: "Lueur", artist: "", album: "", isPlaying: true)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: lueur, audible: false) == false)
        // Another video, silent: not shown
        #expect(TitlePlayback.isPlaying(title: "Autre", previous: lueur, audible: false) == nil)
    }

    @Test func aButtonPressIsTrustedForAMoment() {
        var paused = NowPlaying(player: .youtube, title: "Lueur", artist: "", album: "", isPlaying: false)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: paused, audible: true, pressedRecently: true) == false)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: paused, audible: true) == true)
        paused.isPlaying = true
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: paused, audible: false, pressedRecently: true) == true)
    }

    @Test func withoutTheSoundTheLastButtonDecides() {
        let paused = NowPlaying(player: .deezer, title: "Lueur", artist: "", album: "", isPlaying: false)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: paused, audible: nil) == false)
        #expect(TitlePlayback.isPlaying(title: "Lueur", previous: nil, audible: nil) == true)
        #expect(TitlePlayback.isPlaying(title: "Autre", previous: paused, audible: nil) == true)
    }
}
