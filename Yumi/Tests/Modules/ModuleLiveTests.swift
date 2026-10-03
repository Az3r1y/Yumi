import Testing
import Foundation

/// What each module tells the folded island (ModuleSnapshot.live).
@Suite struct ModuleLiveTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Claude Code

    private func sessions(_ events: [YumiEvent]) -> [Session] {
        ClaudeSessions.ordered(events.reduce(into: [SessionID: Session]()) { $0 = SessionReducer.apply($1, to: $0) })
    }
    private let a = SessionID("a"), b = SessionID("b")
    private func started(_ id: SessionID, _ folder: String) -> [YumiEvent] {
        [.sessionStarted(id, ClaudeHookTranslator.agent, title: folder),
         .sessionLocated(id, SessionOrigin(workingDirectory: "/dev/\(folder)"))]
    }

    @Test func claudeIsSilentWhileSessionsOnlyWork() {
        let working = sessions(started(a, "yumi") + [.toolStarted(a, ToolInfo(name: "Edit", summary: "main.swift"))])
        #expect(ClaudeSessions.snapshot(working).live == nil)
        #expect(ClaudeSessions.snapshot([]).live == nil)
    }

    @Test func claudeAsksForAttentionWhenAnApprovalIsPending() {
        let waiting = sessions(started(a, "yumi") + started(b, "site")
                               + [.permissionRequested(a, PermissionRequest(tool: "Bash", command: "swift test")),
                                  .toolStarted(b, ToolInfo(name: "Read"))])
        let live = ClaudeSessions.snapshot(waiting).live
        #expect(live?.text == "2 sessions · accord sur yumi")
        #expect(live?.priority == ModuleLivePriority.attention)
        #expect(live?.controls == [ModuleControl(id: "primary", symbol: "eye.fill", label: "Voir")])
    }

    @Test func claudeAsksForAttentionWhenAQuestionIsPending() {
        let asking = sessions(started(a, "yumi") + [.questionRequested(a, Question(text: "Which file?"))])
        #expect(ClaudeSessions.snapshot(asking).live?.text == "Claude t'attend sur yumi")
        #expect(ClaudeSessions.snapshot(asking).live?.priority == ModuleLivePriority.attention)

        // Answered: nothing to say any more.
        let resumed = sessions(started(a, "yumi") + [.questionRequested(a, Question(text: "Which file?")),
                                                     .promptSubmitted(a, text: "main.swift")])
        #expect(ClaudeSessions.snapshot(resumed).live == nil)
    }

    // MARK: Music

    private let lueur = NowPlaying(player: .music, title: "Lueur", artist: "Halo Nord", album: "Premières heures", isPlaying: true)

    @Test func musicShowsTheTrackWithPauseAndNext() {
        let live = MusicSummary.snapshot(lueur, canControl: true).live
        #expect(live?.text == "Lueur · Halo Nord")
        #expect(live?.priority == ModuleLivePriority.activity)
        #expect(live?.controls == [ModuleControl(id: "primary", symbol: "pause.fill", label: "Pause"),
                                   ModuleControl(id: "secondary", symbol: "forward.fill", label: "Suivant")])
    }

    @Test func musicIsSilentWhenNothingPlays() {
        #expect(MusicSummary.snapshot(nil, canControl: true).live == nil)
        var paused = lueur
        paused.isPlaying = false
        // Paused long ago, or since an unknown time: gone.
        #expect(MusicSummary.snapshot(paused, canControl: true).live == nil)
        #expect(MusicSummary.snapshot(paused, canControl: true, pausedFor: MusicSummary.pausedLinger + 1).live == nil)
    }

    @Test func aTrackJustPausedOffersToResumeMoreQuietly() {
        var paused = lueur
        paused.isPlaying = false
        let live = MusicSummary.snapshot(paused, canControl: true, pausedFor: 30).live
        #expect(live?.priority == ModuleLivePriority.ambient)
        #expect(live?.controls.first == ModuleControl(id: "primary", symbol: "play.fill", label: "Lecture"))
        #expect(live?.controls.count == 2)
    }

    @Test func musicWithoutArtistOrWithoutControl() {
        var bare = lueur
        bare.artist = ""
        #expect(MusicSummary.snapshot(bare, canControl: true).live?.text == "Lueur")
        // A build that cannot command the player shows the track without buttons.
        #expect(MusicSummary.snapshot(lueur, canControl: false).live?.controls.isEmpty == true)
    }

    // MARK: Focus

    @Test func focusShowsTheCountdownWithAPauseButton() {
        let t0 = date(1, 10)
        var timer = FocusTimer()
        #expect(timer.snapshot(now: t0).live == nil)

        timer.start(now: t0)
        let live = timer.snapshot(now: t0.addingTimeInterval(6 * 60 + 18)).live
        #expect(live?.text == "18:42")
        #expect(live?.priority == ModuleLivePriority.activity)
        #expect(live?.controls == [ModuleControl(id: "primary", symbol: "pause.fill", label: "Pause")])
    }

    @Test func focusBreakPauseAndEnd() {
        let t0 = date(1, 10)
        var timer = FocusTimer()
        timer.start(now: t0)

        timer.pause(now: t0.addingTimeInterval(60))
        let paused = timer.snapshot(now: t0.addingTimeInterval(600)).live
        #expect(paused?.text == "24:00 en pause")
        #expect(paused?.priority == ModuleLivePriority.ambient)
        #expect(paused?.controls == [ModuleControl(id: "primary", symbol: "play.fill", label: "Reprendre")])

        timer.resume(now: t0.addingTimeInterval(600))
        timer.advance(now: t0.addingTimeInterval(600 + 24 * 60 + 30))
        let rest = timer.snapshot(now: t0.addingTimeInterval(600 + 24 * 60 + 30)).live
        #expect(rest?.text == "Pause 04:30")
        #expect(rest?.controls == [ModuleControl(id: "primary", symbol: "forward.fill", label: "Passer")])

        timer.advance(now: t0.addingTimeInterval(10 * 3600))
        #expect(timer.snapshot(now: t0.addingTimeInterval(10 * 3600)).live == nil)
    }

    @Test func everyLiveControlIsAnActionTheRegistryKnows() {
        var timer = FocusTimer()
        timer.start(now: date(1, 10))
        let lives = [timer.snapshot(now: date(1, 10)).live, MusicSummary.snapshot(lueur, canControl: true).live]
        for control in lives.compactMap({ $0 }).flatMap(\.controls) {
            #expect(ModuleAction(rawValue: control.id) != nil)
        }
    }

    // MARK: Agenda

    private func event(_ title: String, _ start: Date, join: String? = nil) -> AgendaEvent {
        AgendaEvent(id: title, title: title, start: start, end: start.addingTimeInterval(1800),
                    isAllDay: false, location: "", joinURL: join.flatMap(URL.init(string:)))
    }

    @Test func agendaAnnouncesTheNextEventOfTheDay() {
        let live = AgendaSummary.snapshot(events: [event("Point produit", date(1, 14, 30))], access: .granted,
                                          now: date(1, 9), calendar: calendar).live
        #expect(live == ModuleLive(text: "14:30 Point produit", priority: ModuleLivePriority.ambient))
    }

    @Test func agendaOffersToJoinWhenThereIsALink() {
        let live = AgendaSummary.snapshot(events: [event("Point produit", date(1, 14, 30), join: "https://meet.google.com/abc")],
                                          access: .granted, now: date(1, 14, 40), calendar: calendar).live
        #expect(live?.text == "Point produit, en cours")
        #expect(live?.controls == [ModuleControl(id: "primary", symbol: "video.fill", label: "Rejoindre")])
    }

    @Test func agendaAnnouncesWhatComesNextRatherThanWhatIsRunning() {
        let events = [event("Atelier", date(1, 10), join: "https://meet.google.com/abc"), event("Déjeuner", date(1, 12, 30))]
        let live = AgendaSummary.snapshot(events: events, access: .granted, now: date(1, 10, 10), calendar: calendar).live
        #expect(live?.text == "12:30 Déjeuner")
        // The button would join the workshop, not the lunch: it is not offered.
        #expect(live?.controls.isEmpty == true)
    }

    @Test func agendaIsSilentWithoutAnEventToday() {
        func live(_ events: [AgendaEvent], _ access: PermissionState = .granted) -> ModuleLive? {
            AgendaSummary.snapshot(events: events, access: access, now: date(1, 19), calendar: calendar).live
        }
        #expect(live([]) == nil)
        #expect(live([event("Stand-up", date(2, 9, 30))]) == nil)
        #expect(live([event("Point produit", date(1, 20))], .notDetermined) == nil)
    }

    // MARK: Notes and weather

    @Test func notesOnlySpeakUpForALateReminder() {
        func live(_ reminders: [ReminderItem]) -> ModuleLive? {
            NotesSummary.snapshot(notes: ["une note"], reminders: reminders, remindersAccess: .granted,
                                  now: date(1, 10), calendar: calendar).live
        }
        #expect(live([]) == nil)
        #expect(live([ReminderItem(id: "1", title: "Appeler Léa", due: date(1, 16), hasTime: true)]) == nil)
        let late = live([ReminderItem(id: "1", title: "Appeler Léa", due: date(1, 9), hasTime: true)])
        #expect(late?.text == "Rappel : Appeler Léa")
        #expect(late?.priority == ModuleLivePriority.ambient)
        #expect(late?.controls == [ModuleControl(id: "primary", symbol: "checkmark", label: "Terminé")])
    }

    @Test func weatherStaysOutOfTheFoldedIsland() {
        let report = WeatherReport(temperature: 19, code: 63, hours: [])
        #expect(WeatherSummary.snapshot(.ready(report), now: date(1, 10), calendar: calendar).live == nil)
    }
}

@MainActor
@Suite struct ChatAnnouncementTests {
    private func module() -> (ClaudeCodeModule, () -> Int) {
        let module = ClaudeCodeModule(onShow: {})
        var changes = 0
        module.start { changes += 1 }
        return (module, { changes })
    }
    private let writing = ChatActivity(id: "w", kind: .writing, label: "J'écris bonjour.txt")

    @Test func nothingWhileTheChatIsIdle() {
        let (module, _) = module()
        #expect(module.snapshot.live == nil)
        #expect(ChatAnnouncement(nil) == nil)
    }

    @Test func theActionUnderWayIsAnnouncedAsAnActivity() {
        let (module, changes) = module()
        module.announceChat(ChatAnnouncement(ChatLive(text: "", activity: writing)))
        #expect(module.snapshot.live == ModuleLive(text: "J'écris bonjour.txt", priority: ModuleLivePriority.activity))
        #expect(changes() == 1)

        // The text growing does not change the announcement: nothing is republished.
        module.announceChat(ChatAnnouncement(ChatLive(text: "Je", activity: writing)))
        module.announceChat(ChatAnnouncement(ChatLive(text: "Je crée", activity: writing)))
        #expect(changes() == 1)

        module.announceChat(ChatAnnouncement(ChatLive(text: "C'est fait", activity: nil, done: [writing])))
        #expect(module.snapshot.live?.text == "Je réponds")
        module.announceChat(nil)
        #expect(module.snapshot.live == nil)
        #expect(changes() == 3)
    }

    @Test func waitingForAPermissionAsksForAttention() {
        let (module, _) = module()
        let waiting = ChatActivity(id: "b", kind: .waiting, label: "J'attends ton accord", detail: "swift test")
        module.announceChat(ChatAnnouncement(ChatLive(activity: waiting)))
        #expect(module.snapshot.live == ModuleLive(text: "J'attends ton accord", priority: ModuleLivePriority.attention))
    }

    @Test func aSessionWaitingForTheUserStaysAhead() {
        let (module, _) = module()
        let id = SessionID("a")
        var sessions = SessionReducer.apply(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        sessions = SessionReducer.apply(.permissionRequested(id, PermissionRequest(tool: "Bash", command: "ls")), to: sessions)
        module.receive(.permissionRequested(id, PermissionRequest(tool: "Bash", command: "ls")), sessions: sessions)
        module.announceChat(ChatAnnouncement(ChatLive(activity: writing)))
        #expect(module.snapshot.live?.text == "Claude veut ton accord sur yumi")
    }
}
