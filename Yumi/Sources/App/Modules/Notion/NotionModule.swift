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

    /// The date pill: "14:00", "aujourd'hui", "en retard · hier", "en retard · 5 oct.".
    static func pill(_ task: NotionTask, now: Date, calendar: Calendar) -> String {
        guard let due = task.due else { return "" }
        let time = task.hasTime ? FrenchText.clock(due, calendar: calendar) : nil
        guard isLate(task, now: now, calendar: calendar) else { return time ?? loc("aujourd'hui") }
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = time ?? loc("aujourd'hui")
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            day = loc("hier")
        } else {
            let formatter = DateFormatter()
            formatter.locale = AppLanguage.locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
            day = formatter.string(from: due)
        }
        return loc("en retard") + " · " + day
    }

    /// The island's list: the late ones under their heading, then today's. Each opens its page and
    /// can be ticked done (unless being ticked already, or when ticking is not possible).
    /// Then the tasks of the coming week, and the pages edited last in every chosen database.
    static func rows(_ tasks: [NotionTask], upcoming: [NotionTask] = [], recent: [NotionPage] = [],
                     now: Date, calendar: Calendar, canTick: Bool, ticking: Set<String>) -> [ModuleRow] {
        var rows: [ModuleRow] = []
        var heading: String?
        for task in ordered(tasks).prefix(12) {
            let late = isLate(task, now: now, calendar: calendar)
            let section = late ? loc("En retard") : loc("Aujourd'hui")
            rows.append(ModuleRow(id: task.id, title: ApprovalRequest.oneLine(task.title, limit: 80) ?? loc("Sans titre"),
                                  detail: detail(task), state: ticking.contains(task.id) ? .busy : (late ? .failure : .neutral),
                                  label: ticking.contains(task.id) ? loc("à cocher…") : pill(task, now: now, calendar: calendar),
                                  section: section == heading ? nil : section,
                                  action: task.url == nil ? nil : "open:\(task.id)",
                                  check: canTick && !ticking.contains(task.id) ? "done:\(task.id)" : nil))
            heading = section
        }
        for (index, task) in ordered(upcoming).prefix(8).enumerated() {
            rows.append(ModuleRow(id: task.id, title: ApprovalRequest.oneLine(task.title, limit: 80) ?? loc("Sans titre"),
                                  detail: detail(task), state: ticking.contains(task.id) ? .busy : .neutral,
                                  label: ticking.contains(task.id) ? loc("à cocher…") : weekday(task, calendar: calendar),
                                  section: index == 0 ? loc("Cette semaine") : nil,
                                  action: task.url == nil ? nil : "open:\(task.id)",
                                  check: canTick && !ticking.contains(task.id) ? "done:\(task.id)" : nil))
        }
        let listed = Set(rows.map(\.id))
        for (index, page) in recent.filter({ !listed.contains($0.id) }).sorted(by: { $0.edited > $1.edited }).prefix(5).enumerated() {
            rows.append(ModuleRow(id: "page-\(page.id)", title: ApprovalRequest.oneLine(page.title, limit: 80) ?? loc("Sans titre"),
                                  detail: page.base, state: .neutral, label: "", date: page.edited,
                                  section: index == 0 ? loc("Modifié récemment") : nil,
                                  action: page.url == nil ? nil : "open:\(page.id)"))
        }
        return rows
    }

    /// "Tâches · À faire": the database, and the status when there is one.
    static func detail(_ task: NotionTask) -> String {
        let base = task.base.trimmingCharacters(in: .whitespaces)
        guard let status = task.status else { return base }
        return "\(base) · \(status)"
    }

    /// "jeu. 15:00", "lun.".
    static func weekday(_ task: NotionTask, calendar: Calendar) -> String {
        guard let due = task.due else { return "" }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let day = formatter.string(from: due)
        return task.hasTime ? "\(day) \(FrenchText.clock(due, calendar: calendar))" : day
    }
}

/// Notion, as a module: the tasks of today and the late ones, from the databases the person
/// shared with their integration and chose in the settings. Reads; it writes only through the
/// agent runtime, with the person's approval each time: `add_notion_task` adds a page, and a
/// task ticked in the island runs `complete_notion_task`.
@MainActor
final class NotionModule: YumiModule {
    let id = "notion"
    /// Never more than one look a minute; Notion asks for about three requests a second at most.
    static let interval: Duration = .seconds(300)

    private let api: NotionAPI
    private let bases: () -> [NotionBase]
    private var tasks: [NotionTask] = []
    /// The coming week's tasks, and the pages edited last: more than what is due today.
    private var upcoming: [NotionTask] = []
    private var recent: [NotionPage] = []
    private var problem: NotionError?
    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var rowObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var lastLook: Date?
    /// Opens the settings, where Notion is set up. Given by the core.
    private let openSettings: @MainActor () -> Void
    /// Ticks a task done through the agent runtime (its approval, its check). nil: no box to tick.
    var complete: (@MainActor (NotionTask) async -> Void)?
    /// The tasks being ticked, until Notion has been read again.
    private var ticking: Set<String> = []

    init(api: NotionAPI, bases: @escaping () -> [NotionBase] = { NotionBases.load() },
         openSettings: @escaping @MainActor () -> Void = {}) {
        self.api = api
        self.bases = bases
        self.openSettings = openSettings
    }

    /// A task of the list, for the approval of its completion.
    func listed(page id: String) -> NotionTask? { (tasks + upcoming).first { $0.id == id } }

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
        if let problem, tasks.isEmpty, upcoming.isEmpty, recent.isEmpty {
            snapshot.status = loc("Erreur")
            snapshot.title = loc("Notion ne répond pas comme prévu")
            snapshot.subtitle = FrenchText.sentenceStart(problem.reason) + "."
            return snapshot
        }
        let late = tasks.filter { NotionBoard.isLate($0, now: now, calendar: .current) }
        snapshot.status = tasks.isEmpty ? loc("Rien") : "\(tasks.count)"
        snapshot.title = tasks.isEmpty ? loc("Aucune tâche pour aujourd'hui") : (tasks.count == 1 ? loc("Une tâche à faire") : loc("\(tasks.count) tâches à faire"))
        if !late.isEmpty {
            snapshot.subtitle = late.count == 1 ? loc("Une en retard.") : loc("\(late.count) en retard.")
        } else if !upcoming.isEmpty {
            snapshot.subtitle = upcoming.count == 1 ? loc("Rien en retard, une cette semaine.") : loc("Rien en retard, \(upcoming.count) cette semaine.")
        } else {
            snapshot.subtitle = loc("Rien en retard.")
        }
        snapshot.needsAttention = NotionBoard.dueNow(tasks, now: now) != nil
        snapshot.rows = NotionBoard.rows(tasks, upcoming: upcoming, recent: recent, now: now, calendar: .current,
                                         canTick: complete != nil, ticking: ticking)
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
        upcoming = []
        recent = []
        NotionListedTasks.shared.set([])
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
        var coming: [NotionTask] = []
        var pages: [NotionPage] = []
        var failure: NotionError?
        for base in bases() {
            do {
                // A base without a date (clients, documents) still shows its latest pages.
                if base.dateProperty != nil {
                    found += try await api.tasks(in: base, on: Date(), overdue: true)
                    coming += try await api.upcoming(in: base, after: Date())
                }
                pages += try await api.recentPages(in: base)
            } catch {
                // Notion said how long to wait: never sooner, and never more than once a minute.
                if case .rateLimited(let seconds) = error {
                    problem = error
                    onChange?()
                    return .seconds(max(60, seconds))
                }
                // One base that fails (no longer shared…) does not hide the others.
                failure = error
            }
        }
        problem = failure
        lastLook = Date()
        let ordered = NotionBoard.ordered(found)
        if ordered != tasks { tasks = ordered }
        upcoming = NotionBoard.ordered(coming)
        recent = pages
        NotionListedTasks.shared.set(tasks + upcoming)
        onChange?()
        return Self.interval
    }

    private func tick(_ id: String) {
        guard let complete, !ticking.contains(id), let task = (tasks + upcoming).first(where: { $0.id == id }) else { return }
        ticking.insert(id)
        onChange?()
        Task { [weak self] in
            await complete(task)
            guard let self else { return }
            _ = await self.look()
            self.ticking.remove(id)
            self.onChange?()
        }
    }

    private func open(_ row: String) {
        if row.hasPrefix("done:") { return tick(String(row.dropFirst("done:".count))) }
        let links = (tasks + upcoming).map { ($0.id, $0.url) } + recent.map { ($0.id, $0.url) }
        guard row.hasPrefix("open:"), let web = links.first(where: { "open:\($0.0)" == row })?.1 else { return }
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
