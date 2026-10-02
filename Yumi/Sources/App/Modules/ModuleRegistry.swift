import Foundation

/// Owns the modules, starts the selected ones, stops the others, and hands their
/// snapshots, in selection order, to whoever displays them (`AppState.modules`).
@MainActor
final class ModuleRegistry {
    private static let selectionKey = "selectedModules"
    private static let knownKey = "knownModules"

    private let defaults: UserDefaults
    private let modules: [any YumiModule]
    private let onPublish: @MainActor ([ModuleSnapshot]) -> Void
    private var running: Set<String> = []
    private var published: [ModuleSnapshot]?
    private var actionObserver: NSObjectProtocol?

    private(set) var selection: ModuleSelection

    /// - Parameter onPublish: receives the snapshots each time they really change.
    init(modules: [any YumiModule], defaults: UserDefaults = .standard,
         onPublish: @escaping @MainActor ([ModuleSnapshot]) -> Void) {
        self.modules = modules
        self.defaults = defaults
        self.onPublish = onPublish
        let stored = defaults.stringArray(forKey: Self.selectionKey)
        selection = ModuleSelection(stored: stored, available: modules.map(\.id))
        // A module added by an update joins a selection saved before it existed, once.
        let known = selection.welcome(available: modules.map(\.id),
                                      known: stored == nil ? nil : defaults.stringArray(forKey: Self.knownKey) ?? ModuleSelection.firstModules)
        defaults.set(known, forKey: Self.knownKey)
        if stored != nil, selection.ids != stored { defaults.set(selection.ids, forKey: Self.selectionKey) }
    }

    /// Identifiers of every module of this build, in catalogue order.
    var availableIDs: [String] { modules.map(\.id) }

    // MARK: Lifecycle

    func start() {
        actionObserver = NotificationCenter.default.addObserver(
            forName: .moduleAction, object: nil, queue: .main
        ) { [weak self] note in
            let id = note.userInfo?["module"] as? String
            let action = (note.userInfo?["action"] as? String).flatMap(ModuleAction.init(rawValue:))
            MainActor.assumeIsolated {
                guard let self, let id, let action else { return }
                self.perform(action, on: id)
            }
        }
        applySelection()
    }

    /// Stops every module and stops listening to the island.
    func stop() {
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        for module in modules where running.contains(module.id) { module.stop() }
        running.removeAll()
    }

    // MARK: Selection

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    /// Selects or deselects a module. Returns false when nothing changed (unknown module, or selection full).
    @discardableResult
    func setSelected(_ id: String, _ selected: Bool) -> Bool {
        let changed = selected
            ? selection.select(id, available: availableIDs)
            : selection.deselect(id)
        if changed { persistAndApply() }
        return changed
    }

    /// Moves a selected module. Indexes below `ModuleCatalog.pinnedLimit` are in the island.
    func move(_ id: String, to index: Int) {
        let before = selection
        selection.move(id, to: index)
        if selection != before { persistAndApply() }
    }

    private func persistAndApply() {
        defaults.set(selection.ids, forKey: Self.selectionKey)
        applySelection()
    }

    /// Starts what became selected, stops what no longer is, then publishes.
    private func applySelection() {
        for module in modules {
            let wanted = selection.contains(module.id)
            let isRunning = running.contains(module.id)
            if wanted && !isRunning {
                running.insert(module.id)
                module.start { [weak self] in self?.publish() }
            } else if !wanted && isRunning {
                running.remove(module.id)
                module.stop()
            }
        }
        publish()
    }

    // MARK: Snapshots

    /// Rebuilds the snapshots. Publishes only on a real change, so views are not invalidated for nothing.
    func publish() {
        let byID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshots = selection.ids.compactMap { byID[$0]?.snapshot }
        guard snapshots != published else { return }
        published = snapshots
        onPublish(snapshots)
    }

    // MARK: Events and actions

    /// Forwards a session event to the running modules.
    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        for module in modules where running.contains(module.id) {
            module.receive(event, sessions: sessions)
        }
    }

    /// A button was pressed in the island. Ignored for a module that is not running.
    func perform(_ action: ModuleAction, on id: String) {
        guard running.contains(id), let module = modules.first(where: { $0.id == id }) else { return }
        module.perform(action)
        publish()
    }
}
