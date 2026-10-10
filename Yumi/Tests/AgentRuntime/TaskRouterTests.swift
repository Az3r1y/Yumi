import Foundation
import Testing
@testable import Yumi

struct TaskRouterTests {
    @Test func theWordsOfARequestGiveItsKind() {
        #expect(TaskRouter.kind(of: "Cherche sur le web le prix de l'iPhone 18") == .web)
        #expect(TaskRouter.kind(of: "Propose-moi une palette de couleurs pour mon site") == .creative)
        #expect(TaskRouter.kind(of: "Pourquoi ma fonction Swift ne compile pas ?") == .code)
        #expect(TaskRouter.kind(of: "Fais une analyse des avantages et inconvénients de ces deux offres") == .reasoning)
        #expect(TaskRouter.kind(of: "Salut, ça va ?") == .simple)
        #expect(TaskRouter.kind(of: String(repeating: "mot ", count: 40)) == nil)
    }

    @Test func anUnclearRequestIsAskedThenFallsBackOnItsLength() async {
        let unclear = String(repeating: "mot ", count: 40)
        #expect(await TaskRouter.classify(unclear, ask: { _ in "creative" }) == .creative)
        #expect(await TaskRouter.classify(unclear, ask: { _ in nil }) == .simple)
        #expect(await TaskRouter.classify(unclear + String(repeating: "x", count: 300)) == .reasoning)
    }

    @Test func aRouteNamedWithAnAtWins() throws {
        let forced = try #require(TaskRouter.forced("@opus explique-moi ça"))
        #expect(forced.route == TaskRouter.Route(engine: .claudeCode, model: "opus"))
        #expect(forced.message == "explique-moi ça")
        #expect(TaskRouter.forced("@inconnu bonjour") == nil)
        #expect(TaskRouter.forced("écris à @opus") == nil)
    }

    @Test func theRoutedEngineIsTriedFirstWithItsModelThenTheUsualOrder() {
        var settings = EngineSettings()
        settings.order = [.claudeCode, .antigravity, .apple]
        let tries = settings.routed(TaskRouter.Route(engine: .antigravity, model: "gemini-3.1-pro-high"))
        #expect(tries.first?.engine == .antigravity)
        #expect(tries.first?.settings.model(.antigravity) == "gemini-3.1-pro-high")
        #expect(Array(tries.dropFirst().prefix(2).map(\.engine)) == [.claudeCode, .antigravity])
        #expect(settings.routed(nil).map(\.engine) == settings.sequence)
    }

    @Test func routesAreSavedAndReadBack() throws {
        let defaults = try #require(UserDefaults(suiteName: "router-\(UUID().uuidString)"))
        var router = RouterSettings()
        router.enabled = false
        router.routes[.code] = TaskRouter.Route(engine: .antigravity, model: "gemini-3.1-pro-high")
        router.save(to: defaults)
        #expect(RouterSettings.load(from: defaults) == router)
        #expect(TaskRouter.Route(stored: "apple|") == TaskRouter.Route(engine: .apple, model: nil))
    }
}
