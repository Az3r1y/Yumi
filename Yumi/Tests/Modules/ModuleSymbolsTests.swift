import Testing
import Foundation

/// The fields the activity interface draws: module symbol, button symbols, progress bar.
@Suite struct ModuleSymbolsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute))!
    }
    private let lueur = NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "", isPlaying: true, duration: 194)

    /// One snapshot of every state a module can be in.
    private var everySnapshot: [ModuleSnapshot] {
        let event = AgendaEvent(id: "e", title: "Point", start: date(14, 30), end: date(15), isAllDay: false, location: "", joinURL: nil)
        var joinable = event
        joinable.joinURL = URL(string: "https://meet.google.com/abc")
        var focus: [ModuleSnapshot] = [FocusTimer().snapshot(now: date(10))]
        var timer = FocusTimer()
        timer.start(now: date(10)); focus.append(timer.snapshot(now: date(10, 5)))
        timer.pause(now: date(10, 5)); focus.append(timer.snapshot(now: date(10, 6)))
        timer.resume(now: date(10, 6)); timer.advance(now: date(10, 27)); focus.append(timer.snapshot(now: date(10, 27)))
        timer.advance(now: date(20)); focus.append(timer.snapshot(now: date(20)))
        var paused = lueur
        paused.isPlaying = false
        let session = SessionReducer.apply(.sessionLocated(SessionID("s"), SessionOrigin(hostName: "ghostty")),
                                           to: SessionReducer.apply(.sessionStarted(SessionID("s"), ClaudeHookTranslator.agent, title: "y"), to: [:]))
        let report = WeatherReport(temperature: 19, code: 63, hours: [])
        return focus + [
            ClaudeSessions.snapshot([]), ClaudeSessions.snapshot(ClaudeSessions.ordered(session)),
            AgendaSummary.snapshot(events: [], access: .notDetermined, now: date(10), calendar: calendar),
            AgendaSummary.snapshot(events: [], access: .denied, now: date(10), calendar: calendar),
            AgendaSummary.snapshot(events: [], access: .granted, now: date(10), calendar: calendar),
            AgendaSummary.snapshot(events: [event], access: .granted, now: date(10), calendar: calendar),
            AgendaSummary.snapshot(events: [joinable], access: .granted, now: date(10), calendar: calendar),
            NotesSummary.snapshot(notes: [], reminders: [], remindersAccess: .notDetermined, now: date(10), calendar: calendar),
            NotesSummary.snapshot(notes: ["a"], reminders: [ReminderItem(id: "1", title: "x", due: date(9), hasTime: true)],
                                  remindersAccess: .granted, now: date(10), calendar: calendar),
            MusicSummary.snapshot(nil, canControl: true), MusicSummary.snapshot(lueur, canControl: true),
            MusicSummary.snapshot(paused, canControl: true), MusicSummary.snapshot(lueur, canControl: false),
            WeatherSummary.snapshot(.loading, now: date(10), calendar: calendar),
            WeatherSummary.snapshot(.needsLocation(.notDetermined), now: date(10), calendar: calendar),
            WeatherSummary.snapshot(.needsLocation(.denied), now: date(10), calendar: calendar),
            WeatherSummary.snapshot(.unavailable, now: date(10), calendar: calendar),
            WeatherSummary.snapshot(.ready(report), now: date(10), calendar: calendar),
        ]
    }

    @Test func everyButtonOfEveryStateHasItsSymbol() {
        for snapshot in everySnapshot {
            #expect(snapshot.symbol != "circle.fill", "\(snapshot.id)")
            #expect(snapshot.primarySymbol != nil, "\(snapshot.id) : \(snapshot.primaryAction)")
            #expect((snapshot.secondarySymbol != nil) == (snapshot.secondaryAction != nil), "\(snapshot.id) : \(snapshot.secondaryAction ?? "nil")")
        }
    }

    @Test func eachModuleHasItsOwnSymbol() {
        #expect(ClaudeSessions.snapshot([]).symbol == "terminal.fill")
        #expect(AgendaSummary.snapshot(events: [], access: .granted, now: date(10), calendar: calendar).symbol == "calendar")
        #expect(NotesSummary.snapshot(notes: [], reminders: [], remindersAccess: .granted, now: date(10), calendar: calendar).symbol == "note.text")
        #expect(FocusTimer().snapshot(now: date(10)).symbol == "timer")
        #expect(MusicSummary.snapshot(nil, canControl: true).symbol == "music.note")
        #expect(WeatherSummary.snapshot(.loading, now: date(10), calendar: calendar).symbol == "cloud.sun.fill")
        #expect(WeatherSummary.symbol(for: .ready(WeatherReport(temperature: 1, code: 0, hours: []))) == "sun.max.fill")
        #expect(WeatherSummary.symbol(for: .ready(WeatherReport(temperature: 1, code: 73, hours: []))) == "cloud.snow.fill")
        #expect(WeatherSummary.symbol(for: .ready(WeatherReport(temperature: 1, code: 96, hours: []))) == "cloud.bolt.rain.fill")
    }

    @Test func buttonsFollowTheState() {
        let playing = MusicSummary.snapshot(lueur, canControl: true)
        #expect(playing.primarySymbol == "pause.fill" && playing.secondarySymbol == "forward.fill")
        var paused = lueur
        paused.isPlaying = false
        #expect(MusicSummary.snapshot(paused, canControl: true).primarySymbol == "play.fill")
        #expect(MusicSummary.snapshot(nil, canControl: true).primarySymbol == "arrow.up.forward.app.fill")

        var timer = FocusTimer()
        #expect(timer.snapshot(now: date(10)).primarySymbol == "play.fill")
        timer.start(now: date(10))
        #expect(timer.snapshot(now: date(10, 1)).primarySymbol == "pause.fill")
        #expect(timer.snapshot(now: date(10, 1)).secondarySymbol == "stop.fill")
        timer.advance(now: date(10, 26))
        #expect(timer.snapshot(now: date(10, 26)).primarySymbol == "forward.fill")
        timer.advance(now: date(20))
        #expect(timer.snapshot(now: date(20)).primarySymbol == "arrow.counterclockwise")

        var joinable = AgendaEvent(id: "e", title: "Point", start: date(14, 30), end: date(15), isAllDay: false, location: "", joinURL: nil)
        #expect(AgendaSummary.snapshot(events: [joinable], access: .granted, now: date(10), calendar: calendar).primarySymbol == "arrow.up.forward.app.fill")
        joinable.joinURL = URL(string: "https://meet.google.com/abc")
        #expect(AgendaSummary.snapshot(events: [joinable], access: .granted, now: date(10), calendar: calendar).primarySymbol == "video.fill")
        #expect(ModuleSymbols.button("Ouvrir Spotify") == "arrow.up.forward.app.fill")
        #expect(ModuleSymbols.button("Inconnu") == nil)
        #expect(ModuleSymbols.button(nil) == nil)
    }

    // MARK: Progress

    @Test func focusProgressFollowsThePhase() {
        var timer = FocusTimer()
        #expect(timer.snapshot(now: date(10)).progress == nil)
        timer.start(now: date(10))
        #expect(timer.snapshot(now: date(10, 5)).progress == ModuleProgress(fraction: 0.2, leading: "5:00", trailing: "25:00"))
        timer.pause(now: date(10, 5))
        #expect(timer.snapshot(now: date(11)).progress == ModuleProgress(fraction: 0.2, leading: "5:00", trailing: "25:00"))
        timer.resume(now: date(11))
        timer.advance(now: date(11, 21))
        // One minute into the five-minute break.
        #expect(timer.snapshot(now: date(11, 21)).progress == ModuleProgress(fraction: 0.2, leading: "1:00", trailing: "5:00"))
        timer.advance(now: date(20))
        #expect(timer.snapshot(now: date(20)).progress == nil)
    }

    @Test func musicProgressNeedsADurationAndAPosition() {
        #expect(MusicSummary.snapshot(lueur, canControl: true).progress == nil)
        #expect(MusicSummary.snapshot(lueur, canControl: true, position: 112).progress
                == ModuleProgress(fraction: 112.0 / 194.0, leading: "1:52", trailing: "3:14"))
        // A position past the end (a late report) stops at the end.
        #expect(MusicSummary.snapshot(lueur, canControl: true, position: 500).progress?.fraction == 1)
        var unknown = lueur
        unknown.duration = nil
        #expect(MusicSummary.snapshot(unknown, canControl: true, position: 10).progress == nil)
        #expect(MusicSummary.snapshot(nil, canControl: true, position: 10).progress == nil)
    }

    @Test func onlyMusicAndFocusHaveABar() {
        for snapshot in everySnapshot where snapshot.id != "focus" && snapshot.id != "music" {
            #expect(snapshot.progress == nil, "\(snapshot.id)")
        }
    }

    @Test func playersSayHowLongATrackIs() {
        let music = MusicSummary.update(from: ["Name": "Lueur", "Artist": "Halo Nord", "Player State": "Playing", "Total Time": 194_000], player: .music)
        #expect(music == .track(NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "", isPlaying: true, duration: 194)))
        let spotify = MusicSummary.update(from: ["Name": "Lueur", "Player State": "Paused", "Duration": 194_000, "Playback Position": 12.5], player: .spotify)
        #expect(spotify == .track(NowPlaying(player: .spotify, title: "Lueur", artist: "", album: "", isPlaying: false, duration: 194, position: 12.5)))
        // The script answers in seconds for Music, with the decimal mark of the Mac's region.
        let script = MusicSummary.update(fromScriptResult: "Lueur\tHalo Nord\t\tplaying\t112,4\t194,0", player: .music)
        #expect(script == .track(NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "", isPlaying: true, duration: 194, position: 112.4)))
        let spotifyScript = MusicSummary.update(fromScriptResult: "Lueur\tHalo Nord\t\tplaying\t112.4\t194000", player: .spotify)
        #expect(spotifyScript == .track(NowPlaying(player: .spotify, title: "Lueur", artist: "Halo Nord", album: "", isPlaying: true, duration: 194, position: 112.4)))
    }

    @Test func trackTimes() {
        #expect(FrenchText.trackTime(0) == "0:00")
        #expect(FrenchText.trackTime(112.9) == "1:52")
        #expect(FrenchText.trackTime(1500) == "25:00")
        #expect(FrenchText.trackTime(3727) == "1:02:07")
    }
}

@Suite struct PlaybackClockTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let track = NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "", isPlaying: true, duration: 194)

    @Test func aNewTrackStartsAtZeroAndRuns() {
        let clock = PlaybackClock.next(nil, from: nil, to: track, now: t0)
        #expect(clock?.position(at: t0.addingTimeInterval(30)) == 30)
    }

    @Test func pauseFreezesAndResumeContinues() {
        var paused = track
        paused.isPlaying = false
        var clock = PlaybackClock.next(nil, from: nil, to: track, now: t0)
        clock = PlaybackClock.next(clock, from: track, to: paused, now: t0.addingTimeInterval(40))
        #expect(clock?.position(at: t0.addingTimeInterval(500)) == 40)
        clock = PlaybackClock.next(clock, from: paused, to: track, now: t0.addingTimeInterval(500))
        #expect(clock?.position(at: t0.addingTimeInterval(510)) == 50)
    }

    @Test func aReportedPositionWins() {
        var reported = track
        reported.position = 112
        let clock = PlaybackClock.next(PlaybackClock(position: 3, since: t0, isRunning: true), from: track, to: reported, now: t0.addingTimeInterval(5))
        #expect(clock?.position(at: t0.addingTimeInterval(6)) == 113)
    }

    @Test func anotherTrackStartsAgainAndAnUnknownPositionStaysUnknown() {
        var other = track
        other.title = "Autre"
        let clock = PlaybackClock.next(PlaybackClock(position: 90, since: t0, isRunning: true), from: track, to: other, now: t0.addingTimeInterval(100))
        #expect(clock?.position(at: t0.addingTimeInterval(100)) == 0)

        var paused = track
        paused.isPlaying = false
        // Found already paused: where it stopped is not known, and resuming does not make it known.
        #expect(PlaybackClock.next(nil, from: nil, to: paused, now: t0) == nil)
        #expect(PlaybackClock.next(nil, from: paused, to: track, now: t0) == nil)
        #expect(PlaybackClock.next(PlaybackClock(position: 1, since: t0, isRunning: true), from: track, to: nil, now: t0) == nil)
    }
}
