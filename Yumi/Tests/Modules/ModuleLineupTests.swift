import Testing
import Foundation

@MainActor
private final class Plain: YumiModule {
    let id: String
    init(_ id: String) { self.id = id }
    var snapshot: ModuleSnapshot {
        ModuleSnapshot(id: id, name: id.capitalized, colorHex: "#FFFFFF", status: "", title: "", subtitle: "", primaryAction: "Voir")
    }
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
    func perform(_ action: ModuleAction) {}
}

/// Choosing and ordering the modules: one list for the settings and the island.
@MainActor
@Suite struct ModuleLineupTests {
    private func defaults() -> UserDefaults {
        let name = "yumi.lineup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func setUp(_ ids: [String], stored: [String]?, known: [String]? = nil, defaults store: UserDefaults? = nil)
        -> (ModuleRegistry, ModuleLineup, UserDefaults) {
        let store = store ?? defaults()
        if let stored { store.set(stored, forKey: "selectedModules") }
        if let known { store.set(known, forKey: "knownModules") }
        let registry = ModuleRegistry(modules: ids.map(Plain.init), defaults: store) { _ in }
        let lineup = ModuleLineup()
        registry.share(with: lineup)
        return (registry, lineup, store)
    }

    @Test func theShownModulesComeFirstInTheirOrderThenTheHiddenOnes() {
        let (_, lineup, _) = setUp(["claude-code", "agenda", "music", "weather"], stored: ["music", "claude-code"],
                                   known: ["claude-code", "agenda", "music", "weather"])
        #expect(lineup.entries.map(\.id) == ["music", "claude-code", "agenda", "weather"])
        #expect(lineup.selected.map(\.id) == ["music", "claude-code"])
        #expect(lineup.hidden.map(\.id) == ["agenda", "weather"])
    }

    @Test func movingChangesTheOrderAndIsSaved() {
        let (registry, lineup, store) = setUp(["a", "b", "c"], stored: ["a", "b", "c"], known: ["a", "b", "c"])
        lineup.move("c", to: 0)
        #expect(lineup.selected.map(\.id) == ["c", "a", "b"])
        #expect(registry.selection.ids == ["c", "a", "b"])
        #expect(store.stringArray(forKey: "selectedModules") == ["c", "a", "b"])
        lineup.nudge("c", by: 1)
        #expect(lineup.selected.map(\.id) == ["a", "c", "b"])
        lineup.nudge("a", by: -1)
        #expect(lineup.selected.map(\.id) == ["a", "c", "b"])
    }

    @Test func hidingAndShowingAgain() {
        let (registry, lineup, store) = setUp(["a", "b", "c"], stored: ["a", "b", "c"], known: ["a", "b", "c"])
        lineup.setShown("b", false)
        #expect(lineup.selected.map(\.id) == ["a", "c"])
        #expect(lineup.hidden.map(\.id) == ["b"])
        #expect(store.stringArray(forKey: "selectedModules") == ["a", "c"])
        // Shown again, it goes at the end of the shown ones
        lineup.setShown("b", true)
        #expect(lineup.selected.map(\.id) == ["a", "c", "b"])
        withExtendedLifetime(registry) {}
    }

    @Test func theFirstOnesGoInTheIslandTheOthersInTheSecondSquare() {
        #expect(ModuleLineup.place(of: 0, selected: true) == .island)
        #expect(ModuleLineup.place(of: ModuleCatalog.pinnedLimit - 1, selected: true) == .island)
        #expect(ModuleLineup.place(of: ModuleCatalog.pinnedLimit, selected: true) == .secondSquare)
        #expect(ModuleLineup.place(of: 0, selected: false) == .hidden)
    }

    @Test func aNewModuleArrivesAtTheEndVisibleWithoutMovingTheOthers() {
        // The order the person chose, then an update brings "notion"
        let (registry, lineup, store) = setUp(["claude-code", "agenda", "music", "notion"], stored: ["music", "claude-code"],
                                       known: ["claude-code", "agenda", "music"])
        #expect(lineup.selected.map(\.id) == ["music", "claude-code", "notion"])
        #expect(lineup.hidden.map(\.id) == ["agenda"])
        #expect(store.stringArray(forKey: "knownModules")?.contains("notion") == true)
        // Hidden afterwards, it stays hidden at the next launch
        lineup.setShown("notion", false)
        let (registryAgain, again, _) = setUp(["claude-code", "agenda", "music", "notion"], stored: nil, defaults: store)
        #expect(again.selected.map(\.id) == ["music", "claude-code"])
        withExtendedLifetime((registry, registryAgain)) {}
    }

    @Test func aSelectionSavedByAnOlderVersionIsKept() {
        // Saved before "knownModules" existed: the modules of the first version count as known
        let (_, lineup, _) = setUp(["claude-code", "agenda", "notes", "focus", "music", "weather", "github"],
                                   stored: ["weather", "agenda"])
        #expect(Array(lineup.selected.map(\.id).prefix(2)) == ["weather", "agenda"])
        #expect(lineup.selected.map(\.id).last == "github")
        #expect(lineup.hidden.map(\.id) == ["claude-code", "notes", "focus", "music"])
    }
}
