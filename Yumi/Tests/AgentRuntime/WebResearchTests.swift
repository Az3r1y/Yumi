import Foundation
import Testing

// A question searched on the web: the answer apart from its sources, and engines kept to the search.

@Suite struct WebResearchTests {
    @Test func theSourcesComeApartFromTheAnswer() {
        let reply = """
            La dernière version stable est **Swift 6.4**, sortie avec Xcode 27.

            **Sources :**
            - Swift.org : https://swift.org/download
            - https://github.com/swiftlang/swift/releases.
            - [Swift.org](https://swift.org/download)
            """
        let answer = WebResearch.parse(reply)
        #expect(answer.text == "La dernière version stable est **Swift 6.4**, sortie avec Xcode 27.")
        #expect(answer.sources.map(\.url.absoluteString) == ["https://swift.org/download", "https://github.com/swiftlang/swift/releases"])
        #expect(answer.sources.map(\.name) == ["Swift.org", "github.com"])
    }

    @Test func withoutASourcesLineEveryAddressCounts() {
        let answer = WebResearch.parse("Voir [la doc](https://example.com/doc) et https://apple.com.")
        #expect(answer.sources.map { $0.url.host ?? "" } == ["example.com", "apple.com"])
        #expect(WebResearch.parse("Rien de clair.").sources.isEmpty)
    }

    @Test func linksInTheAnswerCannotBeOpenedAndSourcesShowTheirSite() {
        let shown = WebResearch.displayed("Voir **ceci** et [Wikipédia](file:///etc/passwd) ou [doc](x-apple.systempreferences:x)")
        #expect(!shown.runs.contains { $0.link != nil })
        #expect(String(shown.characters) == "Voir ceci et Wikipédia ou doc")
        let spoofed = WebResearch.Source(name: "Wikipédia", url: URL(string: "https://evil.example/login")!)
        #expect(WebResearch.label(spoofed) == "Wikipédia · evil.example")
        #expect(WebResearch.label(.init(name: "apple.com", url: URL(string: "https://www.apple.com")!)) == "apple.com")
    }

    @Test func claudeIsGivenTheWebSearchAndNothingElse() {
        let arguments = ClaudeCodeLLMProvider.arguments(system: "s", model: "sonnet", tools: ["WebSearch", "Bash", "Write"])
        #expect(arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] } == "WebSearch")
        #expect(arguments.firstIndex(of: "--allowedTools").map { arguments[$0 + 1] } == "WebSearch")
        #expect(arguments.firstIndex(of: "--setting-sources").map { arguments[$0 + 1] } == "")
        // As a plain model: no tool at all
        let model = ClaudeCodeLLMProvider.arguments(system: "s", model: nil)
        #expect(model.firstIndex(of: "--tools").map { model[$0 + 1] } == "")
        #expect(!model.contains("--allowedTools"))
    }

    @Test func antigravityIsToldNotToOpenPages() {
        #expect(WebResearch.instructions(for: .antigravity, english: false).contains("sans ouvrir aucune page"))
        #expect(!WebResearch.instructions(for: .claude, english: false).contains("sans ouvrir"))
        #expect(WebResearch.instructions(for: .claude, english: true).contains("Sources:"))
        #expect(WebResearch.instructions(for: .claude, english: false).contains("Fais toujours une recherche"))
    }

    @Test func geminiByDefaultWhenAntigravityIsThere() throws {
        let defaults = try #require(UserDefaults(suiteName: "research-\(UUID().uuidString)"))
        #expect(WebResearch.Engine.stored(defaults, antigravityInstalled: true) == .antigravity)
        #expect(WebResearch.Engine.stored(defaults, antigravityInstalled: false) == .claude)
        defaults.set("claude", forKey: WebResearch.Engine.key)
        #expect(WebResearch.Engine.stored(defaults, antigravityInstalled: true) == .claude)
    }
}
