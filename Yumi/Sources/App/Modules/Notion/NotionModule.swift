import AppKit

/// The databases the person chose, kept in the defaults. Only these are ever read.
enum NotionBases {
    static let key = "notion.bases"

    static func load(from defaults: UserDefaults = .standard) -> [NotionBase] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([NotionBase].self, from: data)) ?? []
    }

    static func save(_ bases: [NotionBase], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(bases), forKey: key)
    }
}

/// What the island lists: the unfinished tasks of today and those late, oldest first.
enum NotionBoard {
    /// Late first, then today's; a task with a time before one without on the same day.
    static func ordered(_ tasks: [NotionTask]) -> [NotionTask] {
        tasks.sorted {
            switch ($0.due, $1.due) {
            case let (a?, b?) where a != b: return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.title < $1.title
            }
        }
    }

    /// Due now: a task with a time between a quarter of an hour ago and in a quarter of an hour.
    static func dueNow(_ tasks: [NotionTask], now: Date) -> NotionTask? {
        tasks.first { task in
            guard task.hasTime, let due = task.due else { return false }
            return abs(due.timeIntervalSince(now)) <= 15 * 60
        }
    }

    static func isLate(_ task: NotionTask, now: Date, calendar: Calendar) -> Bool {
        guard let due = task.due else { return false }
        return task.hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}

/// Notion, as a module: the tasks of today and the late ones, from the databases the person
/// shared with their integration and chose in the settings. Reads, never writes (the agent's
/// `add_notion_task` adds a page, with the person's approval).
@MainActor
final class NotionModule: YumiModule {
    let id = "notion"
    /// Never more than one look a minute; Notion asks for about three requests a second at most.
    static let interval: Duration = .seconds(300)

    private let api: NotionAPI
    private let bases: () -> [NotionBase]
    private var tasks: [NotionTask] = []
    private var problem: NotionError?
    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var rowObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var lastLook: Date?
    /// Opens the settings, where Notion is set up. Given by the core.
    private let openSettings: @MainActor () -> Void

    init(api: NotionAPI, bases: @escaping () -> [NotionBase] = { NotionBases.load() },
         openSettings: @escaping @MainActor () -> Void = {}) {
        self.api = api
        self.bases = bases
        self.openSettings = openSettings
    }

    var snapshot: ModuleSnapshot {
        let now = Date()
        var snapshot = ModuleSnapshot(id: id, name: "Notion", colorHex: "#E8E8E8", status: "", title: "", subtitle: "",
                                      primaryAction: loc("Ouvrir"), symbol: "checklist")
        if api.key()?.nonEmptyTrimmed == nil || bases().isEmpty {
            snapshot.status = loc("À brancher")
            snapshot.title = loc("Branche Notion dans les réglages")
            snapshot.subtitle = loc("Une clé d'intégration et les bases à suivre.")
            snapshot.primaryAction = loc("Ouvrir les réglages")
            return snapshot
        }
        if let problem, tasks.isEmpty {
            snapshot.status = loc("Erreur")
            snapshot.title = loc("Notion ne répond pas comme prévu")
            snapshot.subtitle = FrenchText.sentenceStart(problem.reason) + "."
            return snapshot
        }
        let late = tasks.filter { NotionBoard.isLate($0, now: now, calendar: .current) }
        snapshot.status = tasks.isEmpty ? loc("Rien") : "\(tasks.count)"
        snapshot.title = tasks.isEmpty ? loc("Aucune tâche pour aujourd'hui") : (tasks.count == 1 ? loc("Une tâche à faire") : loc("\(tasks.count) tâches à faire"))
        snapshot.subtitle = late.isEmpty ? loc("Rien en retard.") : (late.count == 1 ? loc("Une en retard.") : loc("\(late.count) en retard."))
        snapshot.needsAttention = NotionBoard.dueNow(tasks, now: now) != nil
        snapshot.rows = tasks.prefix(12).map { task in
            let isLate = NotionBoard.isLate(task, now: now, calendar: .current)
            let when = task.due.map { task.hasTime ? FrenchText.clock($0) : (isLate ? loc("en retard") : loc("aujourd'hui")) } ?? ""
            return ModuleRow(id: task.id, title: ApprovalRequest.oneLine(task.title, limit: 80) ?? loc("Sans titre"),
                             detail: task.base, state: isLate ? .failure : .neutral, label: when,
                             date: task.due, action: task.url == nil ? nil : "open:\(task.id)")
        }
        if let due = NotionBoard.dueNow(tasks, now: now) {
            snapshot.live = ModuleLive(text: "\(FrenchText.clock(due.due ?? now)) \(ApprovalRequest.oneLine(due.title, limit: 30) ?? "")",
                                       priority: ModuleLivePriority.attention - 10)
        }
        return snapshot
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        rowObserver = NotificationCenter.default.addObserver(forName: .moduleRowAction, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["module"] as? String == "notion", let row = note.userInfo?["row"] as? String else { return }
            MainActor.assumeIsolated { self?.open(row) }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .notionSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        restart()
    }

    func stop() {
        onChange = nil
        polling?.cancel()
        polling = nil
        tasks = []
        problem = nil
        for observer in [rowObserver, settingsObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        rowObserver = nil
        settingsObserver = nil
    }

    func perform(_ action: ModuleAction) {
        if api.key()?.nonEmptyTrimmed == nil || bases().isEmpty {
            openSettings()
        } else if let first = tasks.first {
            open("open:\(first.id)")
        } else if let url = URL(string: "notion://") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The tasks of one day, for `get_today`: read when asked. nil when the module is off or not set up.
    func tasks(on day: Date) async -> [NotionTask]? {
        guard onChange != nil, api.key()?.nonEmptyTrimmed != nil, !bases().isEmpty else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(day), problem == nil, lastLook != nil { return tasks }
        var found: [NotionTask] = []
        for base in bases() {
            guard let some = try? await api.tasks(in: base, on: day, overdue: false) else { return nil }
            found += some
        }
        return NotionBoard.ordered(found)
    }

    // MARK: - Private

    private func restart() {
        polling?.cancel()
        guard api.key()?.nonEmptyTrimmed != nil, !bases().isEmpty else {
            tasks = []
            onChange?()
            return
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = await self.look()
                try? await Task.sleep(for: wait, tolerance: .seconds(10))
            }
        }
    }

    /// One look at every chosen database. Returns how long to wait before the next one.
    private func look() async -> Duration {
        var found: [NotionTask] = []
        for base in bases() {
            do {
                found += try await api.tasks(in: base, on: Date(), overdue: true)
            } catch {
                problem = error
                onChange?()
                // Notion said how long to wait: never sooner, and never more than once a minute.
                if case .rateLimited(let seconds) = error { return .seconds(max(60, seconds)) }
                return Self.interval
            }
        }
        problem = nil
        lastLook = Date()
        let ordered = NotionBoard.ordered(found)
        if ordered != tasks { tasks = ordered }
        onChange?()
        return Self.interval
    }

    private func open(_ row: String) {
        guard row.hasPrefix("open:"), let task = tasks.first(where: { "open:\($0.id)" == row }), let web = task.url else { return }
        if let app = NotionAPI.appLink(web), NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            NSWorkspace.shared.open(app)
        } else {
            NSWorkspace.shared.open(web)
        }
    }
}

extension Notification.Name {
    /// Posted by the settings when the key or the chosen databases change.
    static let notionSettingsChanged = AppIdentity.notification("notionSettingsChanged")
}
