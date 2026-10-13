import Testing
import Foundation

@MainActor
private final class FiledModule: YumiModule {
    let id: String
    let tab: ModuleCategory?

    init(_ id: String, tab: ModuleCategory? = nil) { self.id = id; self.tab = tab }

    var category: ModuleCategory { tab ?? ModuleCategory.of(moduleID: id) }
    var snapshot: ModuleSnapshot {
        ModuleSnapshot(id: id, name: id, colorHex: "#FFFFFF", status: "", title: "", subtitle: "", primaryAction: "Voir")
    }
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
    func perform(_ action: ModuleAction) {}
}

@MainActor
@Suite struct ModuleCategoryTests {

    private func makeDefaults() -> UserDefaults {
        let name = "yumi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func eachModuleOfThisBuildHasItsTab() {
        #expect(["claude-code", "github", "notion"].allSatisfy { ModuleCategory.of(moduleID: $0) == .work })
        #expect(["agenda", "weather", "notes"].allSatisfy { ModuleCategory.of(moduleID: $0) == .day })
        #expect(["music", "focus"].allSatisfy { ModuleCategory.of(moduleID: $0) == .relax })
    }

    @Test func anUnknownModuleStillFindsATab() {
        #expect(ModuleCategory.of(moduleID: "a-future-module") == .day)
    }

    @Test func aTabKeepsThePersonsOrder() {
        let ids = ["focus", "notes", "github", "music", "claude-code", "agenda"]
        #expect(ModuleCategory.ids(ids, in: .work) == ["github", "claude-code"])
        #expect(ModuleCategory.ids(ids, in: .relax) == ["focus", "music"])
        #expect(ModuleCategory.present(in: ["music", "github"]) == [.work, .relax])
    }

    @Test func theRegistryFilesEachSnapshotUnderTheModulesOwnTab() {
        let defaults = makeDefaults()
        defaults.set(["music", "claude-code", "radio", "agenda"], forKey: "selectedModules")
        var published: [ModuleSnapshot] = []
        let registry = ModuleRegistry(modules: [FiledModule("claude-code"), FiledModule("music"), FiledModule("agenda"),
                                                FiledModule("radio", tab: .relax)],
                                      defaults: defaults) { published = $0 }
        registry.start()

        #expect(published.map(\.tab) == [.relax, .work, .relax, .day])
        #expect(registry.selected(in: .relax) == ["music", "radio"])
        #expect(registry.selected(in: .work) == ["claude-code"])
    }

    @Test func theLineupGroupsTheShownModulesByTab() {
        let defaults = makeDefaults()
        defaults.set(["focus", "github", "music"], forKey: "selectedModules")
        let registry = ModuleRegistry(modules: [FiledModule("github"), FiledModule("focus"), FiledModule("music"),
                                                FiledModule("weather")],
                                      defaults: defaults) { _ in }
        let lineup = ModuleLineup()
        registry.share(with: lineup)

        #expect(lineup.selected(in: .relax).map(\.id) == ["focus", "music"])
        #expect(lineup.selected(in: .work).map(\.id) == ["github"])
        #expect(lineup.selected(in: .day).isEmpty)
    }

    @Test func aSnapshotWithoutATabTakesTheOneOfItsIdentifier() {
        var snapshot = ModuleSnapshot(id: "weather", name: "", colorHex: "#FFFFFF", status: "", title: "", subtitle: "", primaryAction: "")
        #expect(snapshot.tab == .day)
        snapshot.category = .relax
        #expect(snapshot.tab == .relax)
    }
}
