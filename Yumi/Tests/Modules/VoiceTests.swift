import Testing
import Foundation

/// Everything Yumi says must sound like him (design/yumi/voix.md): no assistant formula, no emoji.
/// This test collects every sentence the modules and the chat can produce, in every state.
@Suite struct VoiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Formulas of an assistant, of a notification, or that lecture: none may appear.
    static let forbidden = [
        "bien sûr", "je suis là pour", "n'hésite pas", "n'hésitez pas", "avec plaisir", "pas de problème", "pas de souci",
        "je serais ravi", "ravi de", "comment puis-je", "puis-je t'aider", "en tant qu'", "assistant", "désolé", "veuillez",
        "merci de", "s'il vous plaît", "votre ", " vous ", "félicitations", "génial", "super !", "bravo", "oups", "attention :",
        "—", "–", "tu devrais", "il faut que tu", "tu aurais dû", "encore en retard", "erreur :", "error", "failed", "!!",
    ]

    static func emoji(in text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { scalar in
            scalar.properties.isEmojiPresentation || (0x1F000...0x1FAFF).contains(scalar.value)
                || (0x2600...0x27BF).contains(scalar.value) || scalar.value == 0xFE0F
        }
    }

    private var snapshots: [ModuleSnapshot] {
        var result: [ModuleSnapshot] = []
        // Claude Code, in every state of a session.
        let agent = ClaudeHookTranslator.agent
        let id = SessionID("s"), other = SessionID("t")
        let origin = SessionOrigin(workingDirectory: "/dev/yumi", hostName: "ghostty")
        let base: [YumiEvent] = [.sessionStarted(id, agent, title: "yumi"), .sessionLocated(id, origin)]
        let states: [[YumiEvent]] = [
            [], [.promptSubmitted(id, text: "go")], [.toolStarted(id, ToolInfo(name: "Edit", summary: "main.swift"))],
            [.toolStarted(id, ToolInfo(name: "Bash", summary: "swift test")), .toolFinished(id, ToolInfo(name: "Bash"))],
            [.permissionRequested(id, PermissionRequest(tool: "Bash", command: "ls"))], [.questionRequested(id, Question(text: "Lequel ?"))],
            [.taskCompleted(id)], [.sessionErrored(id, YumiError(message: "x"))], [.rateLimited(id)],
            [.sessionStarted(other, agent, title: "site"), .permissionRequested(other, PermissionRequest(tool: "Bash")),
             .permissionRequested(id, PermissionRequest(tool: "Bash"))],
        ]
        result.append(ClaudeSessions.snapshot([]))
        for events in states {
            let sessions = (base + events).reduce(into: [SessionID: Session]()) { $0 = SessionReducer.apply($1, to: $0) }
            result.append(ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions)))
        }
        // Agenda.
        let event = AgendaEvent(id: "e", title: "Point produit", start: date(14, 30), end: date(15), isAllDay: false,
                                location: "Salle Lune", joinURL: URL(string: "https://meet.google.com/abc"))
        let tomorrow = AgendaEvent(id: "f", title: "Stand-up", start: date(9, 30, day: 2), end: date(9, 45, day: 2), isAllDay: false, location: "", joinURL: nil)
        for (events, access, now) in [([], PermissionState.notDetermined, date(10)), ([], .denied, date(10)), ([], .granted, date(10)),
                                      ([event], .granted, date(10)), ([event], .granted, date(14, 18)), ([event], .granted, date(14, 40)),
                                      ([tomorrow], .granted, date(19))] {
            result.append(AgendaSummary.snapshot(events: events, access: access, now: now, calendar: calendar))
        }
        // Notes and reminders.
        let late = ReminderItem(id: "1", title: "Appeler Léa", due: date(9), hasTime: true)
        let soon = ReminderItem(id: "2", title: "Envoyer le devis", due: date(16), hasTime: true)
        let today = ReminderItem(id: "3", title: "Courses", due: date(0), hasTime: false)
        let old = ReminderItem(id: "4", title: "Impôts", due: date(0, day: 0), hasTime: false)
        let undated = ReminderItem(id: "5", title: "Un jour", due: nil, hasTime: false)
        for reminders in [[], [late], [soon, today], [old, late, soon], [undated]] {
            result.append(NotesSummary.snapshot(notes: ["Idée : mode nuit"], reminders: reminders, remindersAccess: .granted, now: date(10), calendar: calendar))
        }
        result.append(NotesSummary.snapshot(notes: [], reminders: [], remindersAccess: .notDetermined, now: date(10), calendar: calendar))
        // Focus, through a whole session.
        var timer = FocusTimer()
        result.append(timer.snapshot(now: date(10)))
        timer.start(now: date(10)); result.append(timer.snapshot(now: date(10, 5)))
        timer.pause(now: date(10, 5)); result.append(timer.snapshot(now: date(10, 6)))
        timer.resume(now: date(10, 6)); timer.advance(now: date(10, 27)); result.append(timer.snapshot(now: date(10, 27)))
        timer.pause(now: date(10, 28)); result.append(timer.snapshot(now: date(10, 28)))
        timer.resume(now: date(10, 28)); timer.advance(now: date(20)); result.append(timer.snapshot(now: date(20)))
        // Music.
        let track = NowPlaying(player: .spotify, title: "Lueur", artist: "Halo Nord", album: "Premières heures", isPlaying: true, duration: 194)
        var paused = track
        paused.isPlaying = false
        result += [MusicSummary.snapshot(nil, canControl: true), MusicSummary.snapshot(track, canControl: true, position: 30),
                   MusicSummary.snapshot(paused, canControl: true, pausedFor: 10), MusicSummary.snapshot(track, canControl: false)]
        // Weather.
        let rainLater = WeatherReport(temperature: 19, code: 2, hours: [.init(time: date(18), rainChance: 80)])
        for state in [WeatherState.loading, .needsLocation(.notDetermined), .needsLocation(.denied), .unavailable, .ready(rainLater)]
            + [0, 1, 2, 3, 45, 55, 63, 73, 81, 86, 96, 1234].map({ WeatherState.ready(WeatherReport(temperature: 12, code: $0, hours: [])) }) {
            result.append(WeatherSummary.snapshot(state, now: date(10), calendar: calendar))
        }
        return result
    }

    /// Every sentence Yumi can say, with where it comes from.
    private var sentences: [(String, String)] {
        var all: [(String, String)] = []
        for snapshot in snapshots {
            all.append(("\(snapshot.id) titre", snapshot.title))
            all.append(("\(snapshot.id) sous-titre", snapshot.subtitle))
            all.append(("\(snapshot.id) état", snapshot.status))
            if let live = snapshot.live { all.append(("\(snapshot.id) en direct", live.text)) }
        }
        let tools = ["Read", "Write", "Edit", "Bash", "Grep", "WebSearch", "WebFetch", "Task", "TodoWrite", "mcp__x__y"]
        for name in tools {
            for detail in ["", "/a/notes.txt"] {
                let tool = ChatToolUse(id: "t", name: name, detail: detail)
                all.append(("chat en direct", ChatLiveTracker.activity(for: tool).label))
                for outcome in [ChatToolOutcome.done, .failed, .refused] {
                    if let line = ChatPhrases.action(tool, outcome: outcome) { all.append(("chat action", line)) }
                }
            }
        }
        all.append(("chat en direct", ChatLiveTracker.headline(ChatLive())))
        all.append(("chat en direct", ChatLiveTracker.headline(ChatLive(text: "x"))))
        for text in [ChatPhrases.notInstalled, ChatPhrases.notLoggedIn, ChatPhrases.stopped, ChatPhrases.noAnswer, ChatPhrases.noFolder,
                     ChatPhrases.noKey, ChatPhrases.network, ChatPhrases.unreadable,
                     ChatPhrases.failure(ChatTurnResult(text: "529 overloaded", isError: true, sessionID: nil, errors: []))] {
            all.append(("chat erreur", text))
        }
        return all
    }

    @Test func noAssistantFormulaAnywhere() {
        for (source, text) in sentences {
            let lower = " \(text.lowercased()) "
            for formula in Self.forbidden {
                #expect(!lower.contains(formula), "« \(text) » (\(source)) contient « \(formula) »")
            }
        }
    }

    @Test func noEmojiAnywhere() {
        for (source, text) in sentences {
            #expect(Self.emoji(in: text).isEmpty, "« \(text) » (\(source))")
        }
    }

    @Test func theCheckItselfCatchesWhatItShould() {
        #expect(!Self.emoji(in: "C'est passé ✅").isEmpty)
        #expect(!Self.emoji(in: "Bravo 🎉").isEmpty)
        #expect(!Self.emoji(in: "⚠ failed").isEmpty)
        #expect(Self.emoji(in: "19° · 14:30, « Lueur » à 100 %… Échap").isEmpty)
        #expect(Self.forbidden.contains { " bien sûr ! je regarde. ".contains($0) })
    }

    @Test func titlesAreSentencesAndStayShort() {
        // A title Yumi writes himself is a sentence; a track title or a temperature is not his.
        for snapshot in snapshots where snapshot.id != "music" {
            #expect(snapshot.title.count <= 90, "\(snapshot.title)")
            #expect(snapshot.title.last.map { ".?".contains($0) } == true || snapshot.id == "notes", "\(snapshot.id) : \(snapshot.title)")
        }
    }

    @Test func heSpeaksInTheFirstPersonAndNeverNamesHimself() {
        for (source, text) in sentences {
            #expect(!text.contains("Yumi"), "« \(text) » (\(source))")
        }
    }

    @Test func thePromptCarriesTheVoiceSheet() {
        let prompt = ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/d")
        for rule in ["tu tutoies", "première personne", "deux lignes", "pince-sans-rire", "emoji", "jargon", "douze minutes",
                     "Tu ne prétends jamais", "tiret long"] {
            #expect(prompt.contains(rule), "\(rule)")
        }
        #expect(Self.emoji(in: prompt).isEmpty)
    }

    @Test func smallNumbersAreWrittenInLetters() {
        let expected = [0: "zéro", 1: "un", 12: "douze", 21: "vingt et un", 26: "vingt-six", 70: "soixante-dix", 71: "soixante et onze",
                        77: "soixante-dix-sept", 80: "quatre-vingts", 81: "quatre-vingt-un", 91: "quatre-vingt-onze", 99: "quatre-vingt-dix-neuf"]
        for (value, text) in expected { #expect(FrenchText.spelled(value) == text, "\(value)") }
        #expect(FrenchText.spelled(21, feminine: true) == "vingt et une")
        #expect(FrenchText.spelled(143) == "143")
        #expect(FrenchText.spokenMinutes(12 * 60) == "douze minutes")
        #expect(FrenchText.spokenMinutes(30) == "une minute")
        #expect(FrenchText.spokenMinutes(65 * 60) == "une heure cinq")
        #expect(FrenchText.spelledCount(2, "session", "sessions", feminine: true) == "deux sessions")
    }
}
