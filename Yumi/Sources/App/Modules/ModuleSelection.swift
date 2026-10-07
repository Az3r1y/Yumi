import Foundation

/// The ordered list of modules the user has selected. Pure logic, no storage.
/// Order matters: the first `ModuleCatalog.pinnedLimit` go in the island, the rest in the second square.
struct ModuleSelection: Equatable, Sendable {
    /// Selected on first launch: the modules that work on the Mac without any account.
    static let defaultIDs = ["claude-code", "github", "music", "focus", "notes", "weather", "agenda"]

    /// The modules of the first version: a selection saved without a record of what was known knew these.
    static let firstModules = ["claude-code", "agenda", "notes", "focus", "music", "weather"]

    private(set) var ids: [String]

    /// - Parameters:
    ///   - stored: what was persisted, or nil on first launch.
    ///   - available: identifiers of the modules that exist in this build.
    init(stored: [String]?, available: [String]) {
        var seen = Set<String>()
        ids = (stored ?? Self.defaultIDs)
            .filter { available.contains($0) && seen.insert($0).inserted }
        ids = Array(ids.prefix(ModuleCatalog.selectionLimit))
    }

    /// Adds the modules that did not exist when the selection was saved, once each, at the end,
    /// while there is room.
    /// - Parameter known: the modules the person has already been offered. Returns it completed.
    mutating func welcome(available: [String], known: [String]?) -> [String] {
        guard let known else { return available }
        // Every module the person has never been offered arrives at the end, visible: the
        // order they chose does not move. (Notion, after an update.)
        for id in available where !known.contains(id) { select(id, available: available) }
        return Array(Set(known).union(available)).sorted()
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Adds the module at the end. Returns false when it is unknown, already there, or the selection is full.
    @discardableResult
    mutating func select(_ id: String, available: [String]) -> Bool {
        guard available.contains(id), !ids.contains(id),
              ids.count < ModuleCatalog.selectionLimit else { return false }
        ids.append(id)
        return true
    }

    /// Returns false when the module was not selected.
    @discardableResult
    mutating func deselect(_ id: String) -> Bool {
        guard let index = ids.firstIndex(of: id) else { return false }
        ids.remove(at: index)
        return true
    }

    /// Moves a selected module to `index` (clamped). Used to pin or unpin it.
    mutating func move(_ id: String, to index: Int) {
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: min(max(index, 0), ids.count))
    }
}
