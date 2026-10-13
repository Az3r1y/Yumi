import Foundation

// MARK: - Module system
// A module is one thing Yumi watches. It turns whatever it observes (hook events, the
// calendar, a timer, an API) into a single `ModuleSnapshot` (see Contracts/ModuleTypes.swift).
// The registry keeps `AppState.modules` in step with the selected modules.

/// Which button of the module's detail view was pressed.
enum ModuleAction: String, Sendable {
    case primary
    case secondary
    /// Back one step: the previous track. Modules without one treat it as nothing.
    case previous
}

@MainActor
protocol YumiModule: AnyObject {
    /// Stable identifier, also the `id` of the snapshot and the value persisted in the selection.
    var id: String { get }

    /// What the island should draw right now. Cheap: called every time the module reports a change.
    var snapshot: ModuleSnapshot { get }

    /// Starts observing. Called when the module becomes selected. The module calls
    /// `onChange` each time its snapshot may have changed.
    func start(onChange: @escaping @MainActor () -> Void)

    /// Stops every timer, observer and request. Called when the module is deselected.
    /// A stopped module costs nothing.
    func stop()

    /// A button of the module was pressed in the island.
    func perform(_ action: ModuleAction)

    /// A session event went through the engine. `sessions` is the state after the event.
    func receive(_ event: YumiEvent, sessions: [SessionID: Session])

    /// The tab of the open island it goes in: Travail, Journée or Détente.
    var category: ModuleCategory { get }
}

extension YumiModule {
    var category: ModuleCategory { ModuleCategory.of(moduleID: id) }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {}
}
