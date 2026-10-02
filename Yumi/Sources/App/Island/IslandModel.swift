import SwiftUI

/// What the island knows on top of `AppState`: its shape during the launch, the module it
/// shows, the second square, and what it last asked Yumi to do.
@MainActor
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    /// Set once by the window controller, from the screen the island lives on.
    @Published var layout = IslandLayout()

    // MARK: Launch

    /// The shape of the island while the launch plays; nil the rest of the time.
    @Published var launchStage: IslandStage?
    /// The classes of `.greet` in the mock-up: lit, say, bye.
    @Published var greeting = GreetingPhase()
    /// The sequence playing is the goodbye, not the launch.
    @Published var leaving = false
    /// When the rings and the sparks of the greeting started.
    @Published var sparksStart: Date?
    /// True for the one change that must not be animated (the mock-up's `snap`).
    @Published var snap = false

    struct GreetingPhase: Equatable {
        var lit = false
        var say = false
        var bye = false
    }

    // MARK: Folded island

    /// The live module shown on the right of the notch: kept while another one only ties with it.
    @Published var liveModuleID: String?
    /// The pointer is on the folded island: the buttons of the live module are out.
    @Published var foldedHover = false
    /// How many of those buttons there are, for the window controller's hit test.
    var foldedControls = 0

    // MARK: Open island

    @Published var selectedModuleID: String?
    /// Height the open island needs for what it shows: it is as low as the content allows.
    @Published var openHeight: CGFloat = IslandConst.openHeightDefault

    // MARK: What the agent has been doing (for "Depuis 12 min, 3 fichiers modifiés")

    @Published var workStart: Date?
    @Published var workEnd: Date?
    @Published var filesTouched: Set<String> = []

    // MARK: Yumi

    /// The habit last asked for. His caption follows it.
    @Published private(set) var habit: YumiHabit?
    private var sentMood: YumiMood?
    private var sentRim: YumiRimTone?
    private var lateHabit: DispatchWorkItem?
    private var winkBack: DispatchWorkItem?

    /// The character view is in the window and listens to the commands.
    private(set) var actorReady = false
    private var whenReady: [() -> Void] = []

    private init() {}

    // MARK: - Shape

    func stage(for mode: IslandMode) -> IslandStage {
        if let launchStage { return launchStage }
        switch mode {
        case .hidden:   return .hidden
        case .compact:  return .compact
        case .expanded: return .open
        }
    }

    func islandSize(for mode: IslandMode) -> CGSize {
        layout.size(stage(for: mode), openHeight: openHeight)
    }

    // MARK: - Modules

    /// The module with dedicated screens (working, alert, finished, error): the home view
    /// does not repeat it.
    static let agentModuleID = "claude-code"

    func pinned(_ modules: [ModuleSnapshot]) -> [ModuleSnapshot] {
        Array(modules.prefix(ModuleCatalog.pinnedLimit))
    }

    func others(_ modules: [ModuleSnapshot]) -> [ModuleSnapshot] {
        Array(modules.dropFirst(ModuleCatalog.pinnedLimit).prefix(ModuleCatalog.selectionLimit - ModuleCatalog.pinnedLimit))
    }

    func selectedModule(in modules: [ModuleSnapshot]) -> ModuleSnapshot? {
        modules.first { $0.id == selectedModuleID } ?? modules.first
    }

    /// The one thing the home view shows: what needs the user now, else the next thing to know.
    func featuredModule(in modules: [ModuleSnapshot]) -> ModuleSnapshot? {
        modules.first { $0.needsAttention }
            ?? modules.first { $0.id != Self.agentModuleID }
            ?? modules.first
    }

    static func isBusy(_ state: BotState) -> Bool {
        state == .working || state == .thinking || state == .searching
    }

    nonisolated static func isMusic(_ moduleID: String?) -> Bool {
        moduleID == "music" || moduleID == "musique"
    }

    // MARK: - Agent activity

    func track(state old: BotState, _ new: BotState) {
        let busy: Set<BotState> = [.working, .thinking, .searching]
        let paused: Set<BotState> = [.approval, .question]
        if busy.contains(new), !busy.contains(old), !paused.contains(old) {
            workStart = .now
            workEnd = nil
            filesTouched = []
        }
        if new == .finished || new == .error, workEnd == nil { workEnd = .now }
        if new == .idle, old != .finished { workStart = nil }
    }

    /// Steps look like "Modifie · IslandRootView.swift" (HookServer.frenchStep).
    func track(step: String?) {
        guard let step else { return }
        for verb in ["Modifie · ", "Écrit · "] where step.hasPrefix(verb) {
            filesTouched.insert(String(step.dropFirst(verb.count)))
        }
    }

    // MARK: - Commanding Yumi (Contracts/CharacterCommands.swift)

    func actorAppeared() {
        actorReady = true
        let pending = whenReady
        whenReady = []
        pending.forEach { $0() }
    }

    /// Runs `work` once the character can hear commands.
    func onActorReady(_ work: @escaping () -> Void) {
        if actorReady { work() } else { whenReady.append(work) }
    }

    func pose(_ pose: YumiPose) {
        NotificationCenter.default.post(name: .yumiPose, object: pose)
    }

    func setHabit(_ newHabit: YumiHabit?) {
        habit = newHabit
        NotificationCenter.default.post(name: .yumiHabit, object: newHabit)
    }

    /// The character clears the gaze and any passing face on every mood it receives, so a
    /// mood is only sent when it changes. Send the gaze after it.
    func setMood(_ mood: YumiMood?, force: Bool = false) {
        guard force || mood != sentMood else { return }
        sentMood = mood
        NotificationCenter.default.post(name: .yumiMood, object: mood)
    }

    /// A small sign that he learnt something: a wink, then the face he had.
    func wink() {
        let before = sentMood
        winkBack?.cancel()
        NotificationCenter.default.post(name: .yumiMood, object: YumiMood.wink)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .yumiMood, object: self.sentMood ?? before)
        }
        winkBack = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    func setRim(_ tone: YumiRimTone?) {
        guard tone != sentRim else { return }
        sentRim = tone
        NotificationCenter.default.post(name: .yumiRim, object: tone)
    }

    func setLit(_ on: Bool) {
        NotificationCenter.default.post(name: .yumiLit, object: on)
    }

    func setGaze(_ point: CGPoint?) {
        NotificationCenter.default.post(name: .yumiGaze, object: point)
    }

    /// What the island is doing, as far as Yumi is concerned.
    struct Situation: Equatable {
        var stage: IslandStage
        /// The screen shown, or the one that would be if the island were open.
        var screen: IslandScreen
        var moduleID: String?
        var smokes: Bool
        /// The live module is the music, and it is playing.
        var music = false
        /// The chat is carrying out an action right now (reading, writing, running).
        var chatActs = false
        /// An agent is at work.
        var busy = false
    }

    /// `STATES` of the mock-up: the face, the rim colour, the habit and the pose of each view.
    /// The character already follows `AppState.effectiveState` by itself; the island adds
    /// what only it knows.
    func direct(from old: Situation?, to new: Situation) {
        guard launchStage == nil, new.stage == .open || new.stage == .compact || new.stage == .hidden else { return }

        if new.stage == .hidden {
            cancelLateHabit()
            setHabit(nil)
            setMood(nil)
            setRim(nil)
            return
        }

        let open = new.stage == .open
        let stageChanged = old?.stage != new.stage
        let viewChanged = old?.screen != new.screen || (new.screen == .module && old?.moduleID != new.moduleID)

        // Face and rim: only for the views the state of the agent knows nothing about.
        var look = open ? Self.look(for: new.screen, moduleID: new.moduleID) : nil
        // Talking: he thinks while there is only text, and works during an action
        if open, new.screen == .talk, new.chatActs { look = (.focused, .work) }
        setMood(look?.mood)
        setRim(look?.rim)

        // Habit. Music playing puts his headphones on wherever nothing else is going on:
        // folded, on the home view, and on the view of the music module.
        let listening = (new.music && (!open || new.screen == .home))
            || (open && new.screen == .module && Self.isMusic(new.moduleID))
        // An agent at work: a cigarette, or a coffee for those who turned the cigarette off.
        // Shown wherever the island is not about something else.
        let atWork = new.busy && (!open || new.screen == .home || new.screen == .working)
        switch new.screen {
        case _ where atWork:
            cancelLateHabit()
            setHabit(new.smokes ? .smoke : .coffee)
        case .error:
            cancelLateHabit()
            setHabit(.cloud)
        case .finished:
            // He celebrates first; the sunglasses drop once he has landed (`late: [1650, 'soleil']`).
            if old?.screen != .finished {
                setHabit(nil)
                let item = DispatchWorkItem { [weak self] in self?.setHabit(.sunglasses) }
                lateHabit = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.65, execute: item)
            }
        default:
            cancelLateHabit()
            setHabit(listening ? .headphones : nil)
        }

        // Pose: `playPose(Y, s.pose || 'pop')` on every view
        if stageChanged {
            pose(open ? Self.pose(for: new.screen) : .pop)
        } else if viewChanged {
            pose(Self.pose(for: new.screen))
        }
    }

    private func cancelLateHabit() {
        lateHabit?.cancel()
        lateHabit = nil
    }

    /// Forgets what was sent, so that the next `direct` sends everything again.
    func forgetCommands() {
        cancelLateHabit()
        sentMood = nil
        sentRim = nil
        habit = nil
    }

    static func look(for screen: IslandScreen, moduleID: String? = nil) -> (mood: YumiMood, rim: YumiRimTone)? {
        switch screen {
        case .module where isMusic(moduleID): return nil   // his headphones bring their own face
        case .module where moduleID == "focus": return (.focused, .think)
        case .module where moduleID == "agenda": return (.neutral, .calm)
        case .settings, .memory: return (.curious, .calm)
        case .welcome: return (.happy, .joy)
        case .home:     return nil   // the state of the agent decides (neutral and calm at rest)
        case .working:  return (.focused, .work)
        case .alert:    return (.surprised, .warn)
        case .finished: return (.happy, .done)
        case .error:    return (.worried, .error)
        case .module:   return (.curious, .calm)
        case .talk:     return (.thinking, .think)
        case .drop:     return (.surprised, .calm)
        }
    }

    static func pose(for screen: IslandScreen) -> YumiPose {
        switch screen {
        case .alert:    return .shake
        case .finished: return .celebrate
        case .error:    return .squash
        case .drop:     return .stretch
        case .welcome: return .wave
        case .home, .working, .module, .talk, .settings, .memory: return .pop
        }
    }

    /// The few words under Yumi (`cap`). A habit says it its own way.
    static func caption(for habit: YumiHabit) -> String {
        switch habit {
        case .smoke:      return "Il bosse dur"
        case .exhausted:  return "J'en peux plus"
        case .coffee:     return "Café d'abord"
        case .headphones: return "Il kiffe"
        case .sunglasses: return "Trop facile"
        case .cloud:      return "Sale journée"
        case .whistle:    return "La la la"
        case .sleep:      return "Chut"
        }
    }
}

// MARK: - Preferences of the island

enum IslandPrefs {
    /// "La cigarette doit pouvoir être désactivée" (YUMI.md).
    static let smokeKey = "habitSmoke"
    /// When Yumi last asked the first name.
    static let nameAskedKey = "firstNameAskedAt"
}
