import AppKit
import Combine
import SwiftUI

/// The filming mode (design/yumi/video.md): launched with `YUMI_STUDIO=1`, the island plays
/// each shot of the video on a key, with careful example data and nothing personal, as many
/// times as needed. No sound, no automatic folding, and the pointer is ignored, so that
/// nothing moves but what the shot asks for. `YUMI_STUDIO_SCALE=1.5` or `2` enlarges the
/// island so that it stays sharp once cropped to a vertical frame. Works in Release builds.
@MainActor
enum IslandStudio {
    static let isOn = ProcessInfo.processInfo.environment["YUMI_STUDIO"] == "1"

    /// 1 unless `YUMI_STUDIO_SCALE` says otherwise (between 1 and 3).
    static let scale: CGFloat = {
        guard isOn, let text = ProcessInfo.processInfo.environment["YUMI_STUDIO_SCALE"],
              let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return 1 }
        return CGFloat(min(3, max(1, value)))
    }()

    private static weak var controller: IslandWindowController?
    private static var monitors: [Any] = []
    private static var timers: [DispatchWorkItem] = []
    private static var lastShot: Int?
    /// What the island must show. The core may publish real modules or speak on its own
    /// while filming: the studio's data is put back at once, so nothing personal shows.
    private static var wanted: [ModuleSnapshot] = []
    private static var guards: Set<AnyCancellable> = []

    private static func show(_ modules: [ModuleSnapshot]) {
        wanted = modules
        AppState.shared.modules = modules
    }

    private static func keepData() {
        let state = AppState.shared
        state.$modules.receive(on: DispatchQueue.main)
            .sink { modules in if modules != wanted { state.modules = wanted } }
            .store(in: &guards)
        state.$remark.receive(on: DispatchQueue.main)
            .sink { remark in if let remark, !remark.id.hasPrefix("studio") { state.remark = nil } }
            .store(in: &guards)
        state.$userName.receive(on: DispatchQueue.main)
            .sink { name in if name != Self.name { state.userName = Self.name } }
            .store(in: &guards)
        state.$memory.receive(on: DispatchQueue.main)
            .sink { memory in if !memory.isEmpty { state.memory = [] } }
            .store(in: &guards)
    }

    // MARK: - Example data: believable, never personal

    static let name = "Alex"

    static func modules(musicPlaying: Bool = true) -> [ModuleSnapshot] {
        var music = ModuleSnapshot(id: "music", name: loc("Musique"), colorHex: "#F58AD9", status: loc("lecture"),
                                   title: loc("Lueur"), subtitle: loc("Halo Nord"), primaryAction: loc("Pause"), secondaryAction: loc("Suivant"))
        music.symbol = "music.note"
        music.primarySymbol = "pause.fill"
        music.secondarySymbol = "forward.end.fill"
        music.progress = ModuleProgress(fraction: 0.58, leading: "1:52", trailing: "3:14")
        if musicPlaying {
            music.live = ModuleLive(text: loc("Lueur · Halo Nord"), priority: ModuleLivePriority.activity, controls: [
                ModuleControl(id: "primary", symbol: "pause.fill", label: loc("Pause")),
                ModuleControl(id: "secondary", symbol: "forward.fill", label: loc("Suivant")),
            ])
        }
        var claude = ModuleSnapshot(id: "claude-code", name: "Claude Code", colorHex: "#FFB547", status: loc("au repos"),
                                    title: loc("Rien en cours"), subtitle: loc("Atelier, dernière session il y a une heure"),
                                    primaryAction: loc("Voir"), secondaryAction: nil)
        claude.symbol = "terminal.fill"
        var agenda = ModuleSnapshot(id: "agenda", name: "Agenda", colorHex: "#5B8CFF", status: "14:30",
                                    title: loc("Point produit dans douze minutes"), subtitle: loc("14:30 à 15:00, en visio"),
                                    primaryAction: loc("Rejoindre"), secondaryAction: nil)
        agenda.symbol = "calendar"
        agenda.primarySymbol = "video.fill"
        var notes = ModuleSnapshot(id: "notes", name: "Notes", colorHex: "#F2C744", status: "3",
                                   title: loc("Dernière note"), subtitle: loc("Idée : une page d'accueil plus calme"),
                                   primaryAction: loc("Nouvelle note"), secondaryAction: nil)
        notes.symbol = "note.text"
        var focus = ModuleSnapshot(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: loc("prêt"),
                                   title: loc("Prêt pour une session"), subtitle: loc("vingt-cinq minutes"),
                                   primaryAction: loc("Démarrer"), secondaryAction: nil)
        focus.symbol = "timer"
        focus.primarySymbol = "play.fill"
        var weather = ModuleSnapshot(id: "weather", name: loc("Météo"), colorHex: "#7FD0FF", status: "19°",
                                     title: loc("19° et des éclaircies"), subtitle: loc("Pluie vers 18 h, prends une veste"),
                                     primaryAction: loc("Détail"), secondaryAction: nil)
        weather.symbol = "cloud.sun.fill"
        var github = ModuleSnapshot(id: "github", name: "GitHub", colorHex: "#C9CCDA", status: "128 · 12 · 3",
                                    title: loc("Une étoile de plus sur Atelier."), subtitle: loc("alex/atelier"),
                                    primaryAction: loc("Ouvrir"), secondaryAction: nil)
        github.symbol = "arrow.triangle.branch"
        return [claude, agenda, notes, focus, music, weather, github]
    }

    /// What GetTodayTool answers for tomorrow when asked for the free time, on a day with two
    /// example appointments: 10:00 to 12:00 and 17:00 to 20:00.
    static func freeTimeAnswer(now: Date = .now) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow }
        let events = [
            AgendaEvent(id: "studio-1", title: loc("Point produit"), start: at(10), end: at(12), isAllDay: false, location: ""),
            AgendaEvent(id: "studio-2", title: loc("Atelier client"), start: at(17), end: at(20), isAllDay: false, location: ""),
        ]
        let facts = TodayFacts(events: events, reminders: nil, weather: nil, dayEvents: events)
        return TodayPhrase.reply(facts, day: tomorrow, now: now, freeTime: true, calendar: calendar)
    }

    enum SessionsMoment { case working, waiting, answered }

    /// The example modules with the Claude Code module as ClaudeSessions would make it: one
    /// session at work, or three with one asking, or the same three once it was answered.
    /// Same sentences as the module's (ClaudeSessions.phrase, snapshot, live).
    static func sessions(_ moment: SessionsMoment) -> [ModuleSnapshot] {
        var all = modules(musicPlaying: false)
        guard let index = all.firstIndex(where: { $0.id == "claude-code" }) else { return all }
        let now = Date.now
        var claude = all[index]
        let atelier = ModuleRow(id: "s2", title: loc("atelier"), detail: loc("Modifie Accueil.swift"), state: .busy,
                                label: loc("travaille"), date: now.addingTimeInterval(-720), action: "s2")
        switch moment {
        case .working:
            claude.status = loc("1 session")
            claude.title = loc("Claude modifie Accueil.swift sur atelier.")
            claude.subtitle = loc("Une session ouverte.")
            claude.rows = [atelier]
        case .waiting:
            claude.status = loc("3 sessions")
            claude.title = loc("Claude veut ton accord sur api. Je laisse passer ?")
            claude.subtitle = loc("Trois sessions ouvertes, une t'attend.")
            claude.needsAttention = true
            claude.live = ModuleLive(text: loc("3 sessions · accord sur api"), priority: ModuleLivePriority.attention,
                                     controls: [ModuleControl(id: "primary", symbol: "eye.fill", label: loc("Voir"))])
            claude.rows = [
                ModuleRow(id: "s1", title: loc("api"), detail: loc("Demande Bash : npm test"), state: .waiting,
                          label: loc("attend un accord"), date: now.addingTimeInterval(-40), action: "s1"),
                atelier,
                ModuleRow(id: "s3", title: loc("site"), detail: loc("C'est passé."), state: .success,
                          label: loc("terminée"), date: now.addingTimeInterval(-120), action: "s3"),
            ]
        case .answered:
            claude.status = loc("3 sessions")
            claude.title = loc("C'est passé sur api.")
            claude.subtitle = loc("Trois sessions ouvertes.")
            claude.rows = [
                ModuleRow(id: "s1", title: loc("api"), detail: loc("C'est passé."), state: .success,
                          label: loc("terminée"), date: now, action: "s1"),
                atelier,
                ModuleRow(id: "s3", title: loc("site"), detail: loc("C'est passé."), state: .success,
                          label: loc("terminée"), date: now.addingTimeInterval(-120), action: "s3"),
            ]
        }
        all[index] = claude
        return all
    }

    // MARK: - Starting

    static func startIfRequested(controller: IslandWindowController) {
        guard isOn, self.controller == nil else { return }
        self.controller = controller
        SoundEngine.shared.enabled = false
        controller.holdsOpen = true
        controller.fsm.petitToHiddenDelay = 86_400
        applyData()
        keepData()

        // Keys work whether the island is in front or not: a local monitor when it is,
        // a global one when another application is (this one needs the Accessibility
        // permission, like the Escape key of the island).
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let handled = MainActor.assumeIsolated { key(event.keyCode) }
            return handled ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            let code = event.keyCode
            MainActor.assumeIsolated { _ = key(code) }
        }) { monitors.append(monitor) }

        if let folder = ProcessInfo.processInfo.environment["YUMI_STUDIO_SHOTS"] { rehearse(into: folder) }
    }

    /// `YUMI_STUDIO_SHOTS=<folder>` plays every shot in turn and saves a picture of the island
    /// twice a second, to check the mode without filming.
    /// `YUMI_STUDIO_ONLY=10,11,12` plays only these shots, in this order.
    private static func rehearse(into folder: String) {
        let lengths: [Int: Double] = [1: 6, 2: 9, 3: 5, 4: 9, 5: 8, 6: 9, 7: 4, 8: 12, 9: 6, 10: 8, 11: 12, 12: 15]
        let only = (ProcessInfo.processInfo.environment["YUMI_STUDIO_ONLY"] ?? "")
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let shots = only.isEmpty ? Array(1...9) : only
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            for shot in shots {
                play(shot)
                for frame in 0..<Int((lengths[shot] ?? 6) * 2) {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let view = controller?.window?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(String(format: "shot%d-%02d.png", shot, frame))
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// The core may publish its own state: the studio's data comes back at every shot.
    private static func applyData(musicPlaying: Bool = false) {
        let state = AppState.shared
        state.userName = name
        show(modules(musicPlaying: musicPlaying))
        state.memory = []
        state.remark = nil
        state.chatLive = nil
        state.chatHistory = []
        state.promptContext = nil
        state.droppedFile = nil
        state.pendingApproval = nil
        state.isPinned = false
        state.stateOverride = .idle
        if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks[i].name = loc("atelier")
            state.tasks[i].steps = ["Lit · README.md", "Modifie · Accueil.swift", loc("Exécute · swift test")]
        }
        IslandModel.shared.studioPress = false
    }

    // MARK: - Keys

    /// 1 to 9 play a shot, and the three keys after them (0, then the two to its right) play
    /// shots 10 to 12. Space plays the last one again, Escape puts Yumi back at rest, R folds
    /// the island.
    private static func key(_ code: UInt16) -> Bool {
        let shots: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10, 27: 11, 24: 12]
        if let shot = shots[code] { play(shot); return true }
        switch code {
        case 49: if let lastShot { play(lastShot) }; return true        // Space
        case 53: rest(); return true                                     // Escape
        case 15: cancel(); controller?.collapse(); return true           // R
        default: return false
        }
    }

    private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private static func cancel() {
        timers.forEach { $0.cancel() }
        timers = []
    }

    /// Yumi at rest in the folded island, nothing live, nothing pending.
    static func rest() {
        cancel()
        applyData()
        IslandModel.shared.setHabit(nil)
        controller?.studioRest()
    }

    // MARK: - The shots of design/yumi/video.md

    static func play(_ shot: Int) {
        guard let controller else { return }
        lastShot = shot
        let state = AppState.shared
        let model = IslandModel.shared
        rest()

        switch shot {
        case 1:
            // The full launch
            controller.studioLaunch()

        case 2:
            // A permission, a click on the green button, and he celebrates
            after(0.6) {
                state.stateOverride = .approval
                state.pendingApproval = ApprovalInfo(sessionId: "studio", tool: "Bash", command: "swift test")
                controller.expand(to: .approval)
            }
            after(3.0) { model.studioPress = true }
            after(3.25) {
                model.studioPress = false
                state.pendingApproval = nil
                state.stateOverride = .finished
                state.view = .finished
            }
            after(8.5) { state.stateOverride = .idle }

        case 3:
            // The music starts, he puts his headphones on
            after(0.6) {
                show(modules(musicPlaying: true))
                model.selectedModuleID = "music"
                controller.expand(to: .module)
            }

        case 4:
            // The chat writes itself, then a file is created
            after(0.6) {
                state.stateOverride = .thinking
                state.chatHistory = [ChatMessage(role: .user, content: loc("Écris-moi un petit mot de bienvenue pour le site, et enregistre-le."))]
                controller.expand(to: .prompt)
            }
            var live = ChatLive()
            var at = 1.8
            for word in loc("Je m'en occupe. Quelques lignes simples, puis je range le fichier dans Téléchargements.").split(separator: " ") {
                at += 0.08
                let text = String(word)
                after(at) {
                    live.text += (live.text.isEmpty ? "" : " ") + text
                    state.chatLive = live
                }
            }
            let lines = [loc("Bienvenue."), "", loc("Ici, on prend le temps de bien faire."), loc("Installe-toi, regarde autour de toi,"), loc("et écris-nous si tu as une question.")]
            for (index, _) in lines.enumerated() {
                after(at + 0.5 + Double(index) * 0.35) {
                    live.activity = ChatActivity(id: "w1", kind: .writing, label: loc("Écrit bienvenue.txt"),
                                                 detail: lines[0...index].joined(separator: "\n"))
                    state.chatLive = live
                }
            }
            let end = at + 0.5 + Double(lines.count) * 0.35 + 0.5
            after(end) {
                live.done = [ChatActivity(id: "w1", kind: .writing, label: loc("Écrit bienvenue.txt"))]
                live.activity = nil
                live.text += loc(" C'est fait : bienvenue.txt t'attend.")
                state.chatLive = live
            }
            after(end + 1.0) {
                let text = live.text
                state.chatLive = nil
                state.stateOverride = .idle
                state.chatHistory.append(ChatMessage(role: .assistant, content: text))
            }

        case 5:
            // Folded, he speaks first
            after(0.8) {
                state.remark = YumiRemark(id: "studio-\(Date.now.timeIntervalSince1970)",
                                          text: loc("Deux heures d'affilée. Une pause ?"), mood: .worried, duration: 6)
            }
            after(7.5) { state.remark = nil }

        case 6:
            // His moods, one after the other: coffee, matcha, cloud, sunglasses, sleep
            after(0.5) { controller.expand(to: .overview) }
            let habits: [YumiHabit] = [.coffee, .matcha, .cloud, .sunglasses, .sleep]
            for (index, habit) in habits.enumerated() {
                after(1.6 + Double(index) * 1.5) {
                    model.setHabit(habit)
                    if habit != .sleep { model.pose(.pop) }
                }
            }
            after(1.6 + Double(habits.count) * 1.5 + 0.8) { model.setHabit(nil) }

        case 7:
            // Yumi alone in his light, and a wink
            controller.studioPortrait()
            after(1.4) { model.setMood(.wink, force: true) }
            after(2.6) { model.setMood(.happy, force: true) }

        case 8:
            // GitHub: a star, a fork, a merge
            after(0.5) {
                model.selectedModuleID = "github"
                controller.expand(to: .module)
            }
            let scenes: [(YumiScene, String, String)] = [
                (.star, loc("Une étoile de plus sur Atelier."), "129 · 12 · 3"),
                (.fork, loc("Quelqu'un a copié Atelier pour y travailler."), "129 · 13 · 3"),
                (.merge, loc("La pull request « Accueil plus calme » est fusionnée."), "129 · 13 · 2"),
            ]
            for (index, scene) in scenes.enumerated() {
                after(1.8 + Double(index) * 3.2) {
                    var changed = wanted
                    if let i = changed.firstIndex(where: { $0.id == "github" }) {
                        changed[i].title = scene.1
                        changed[i].status = scene.2
                    }
                    show(changed)
                    NotificationCenter.default.post(name: .yumiScene, object: scene.0)
                }
            }

        case 9:
            // The goodbye
            controller.studioGoodbye()

        case 10:
            // Tomorrow's free time, asked in the chat. The answer goes through the agent runtime
            // in the app (get_today), which this mode does not run: the sentence is written by
            // the tool's own code, from two example appointments, and arrives as a whole, as
            // the runtime's answers do
            after(0.6) {
                state.stateOverride = .thinking
                state.chatHistory = [ChatMessage(role: .user, content: loc("Combien de temps libre j'ai demain pour avancer sur Yumi ?"))]
                controller.expand(to: .prompt)
            }
            after(2.6) {
                state.chatHistory.append(ChatMessage(role: .assistant, content: freeTimeAnswer()))
                state.stateOverride = .idle
                model.setMood(.happy, force: true)
                model.pose(.celebrate)
            }

        case 11:
            // An agent at work, and Yumi with his matcha: folded first, then open on the
            // session, where he is large enough for the bowl to be seen
            after(0.4) {
                show(sessions(.working))
                state.stateOverride = .working
                model.setHabit(.matcha)
            }
            after(3.0) {
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }

        case 12:
            // Three sessions, one waits for an answer; it is given from the notch
            after(0.5) {
                show(sessions(.waiting))
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }
            after(4.5) {
                // The approval is the one of the api session
                if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
                    state.tasks[i].name = loc("api")
                    state.tasks[i].steps = ["Exécute · npm test"]
                }
                state.stateOverride = .approval
                state.pendingApproval = ApprovalInfo(sessionId: "studio", tool: "Bash", command: "npm test")
                controller.expand(to: .approval)
            }
            after(7.1) { model.studioPress = true }
            after(7.35) {
                model.studioPress = false
                state.pendingApproval = nil
                state.stateOverride = .finished
                state.view = .finished
            }
            after(9.7) {
                state.stateOverride = .idle
                show(sessions(.answered))
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }

        default:
            break
        }
    }
}
