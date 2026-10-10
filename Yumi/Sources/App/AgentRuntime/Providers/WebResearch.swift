import Foundation

/// A question answered from the web, in a few sentences, with its sources. Asked to Antigravity
/// (Gemini, on the person's Google account) or to Claude Code (their Claude subscription), each
/// allowed the web search alone: nothing on the Mac is read or changed.
enum WebResearch {
    enum Engine: String, CaseIterable, Sendable {
        case antigravity, claude
        static let key = "research.engine"

        var label: String {
            switch self {
            case .antigravity: loc("Gemini (Antigravity)")
            case .claude: "Claude"
            }
        }

        /// The one chosen, else Antigravity when it is installed, else Claude.
        static func stored(_ defaults: UserDefaults = .standard, antigravityInstalled: Bool) -> Engine {
            defaults.string(forKey: key).flatMap(Engine.init(rawValue:)) ?? (antigravityInstalled ? .antigravity : .claude)
        }
    }

    enum Depth: String, CaseIterable, Sendable {
        case quick, deep
        static let key = "research.depth"

        var label: String {
            switch self {
            case .quick: loc("Rapide")
            case .deep: loc("Approfondie")
            }
        }

        /// The model for each depth: Flash answers in seconds, Pro digs longer.
        var antigravityModel: String {
            switch self {
            case .quick: "gemini-3.8-flash-medium"
            case .deep: "gemini-3.1-pro-high"
            }
        }

        var claudeModel: String? {
            switch self {
            case .quick: "sonnet"
            case .deep: "opus"
            }
        }
    }

    struct Source: Equatable, Hashable, Sendable {
        /// The site's name as the engine gave it; the address's host otherwise.
        var name: String
        var url: URL
    }

    struct Answer: Equatable, Sendable {
        /// The answer without its list of sources (Markdown links kept).
        var text: String
        var sources: [Source]
    }

    static func instructions(for engine: Engine, english: Bool) -> String {
        let pagesRule = engine == .antigravity
            ? (english ? " Use only the web search, without opening any page." : " Utilise uniquement la recherche web, sans ouvrir aucune page.")
            : ""
        return english
            ? "Always search the web before answering the person's question, even when you think you know.\(pagesRule) Answer in English in two to five sentences, straight to the point: no greeting, no introduction, no title. End with a line « Sources: » then one line per source: « - Site name: address »."
            : "Fais toujours une recherche sur le web avant de répondre à la question de la personne, même si tu crois savoir.\(pagesRule) Réponds en français en deux à cinq phrases, droit au but : sans salutation, sans te présenter, sans titre. Termine par une ligne « Sources : » puis une ligne par source : « - Nom du site : adresse »."
    }

    /// Splits the answer from its sources: the addresses after « Sources », or else every web
    /// address in the text, each once.
    static func parse(_ reply: String) -> Answer {
        let lines = reply.components(separatedBy: .newlines)
        let start = lines.lastIndex { line in
            let plain = line.lowercased().replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            return plain.hasPrefix("sources") || plain.hasPrefix("source :") || plain.hasPrefix("source:")
        }
        let body = start.map { lines[..<$0].joined(separator: "\n") } ?? reply
        let tail = start.map { lines[$0...].joined(separator: "\n") } ?? reply
        var seen: Set<String> = []
        var sources: [Source] = []
        for line in tail.components(separatedBy: .newlines) {
            for match in line.matches(of: /https?:\/\/[^\s)\]>"'«»]+/) {
                let address = String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
                guard seen.insert(address).inserted, let url = URL(string: address), let host = url.host,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
                // « - Wikipédia : https://… » or « [Wikipédia](https://…) »: the name before the address
                let before = line[..<match.range.lowerBound]
                    .replacingOccurrences(of: "](", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -*•:[]()").union(.whitespaces))
                let name = before.isEmpty || before.count > 60 ? host.replacingOccurrences(of: "www.", with: "") : before
                sources.append(Source(name: name, url: url))
            }
        }
        return Answer(text: body.trimmingCharacters(in: .whitespacesAndNewlines), sources: sources)
    }

    /// The answer as shown: bold and italics kept, no link. What a model writes from pages it
    /// read could dress any address as anything; only the listed sources can be opened.
    static func displayed(_ text: String) -> AttributedString {
        var shown = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in shown.runs where run.link != nil { shown[run.range].link = nil }
        return shown
    }

    /// "Wikipédia · fr.wikipedia.org": the name the engine gave, and the site it really opens.
    static func label(_ source: Source) -> String {
        let host = (source.url.host ?? source.url.absoluteString).replacingOccurrences(of: "www.", with: "")
        return source.name.caseInsensitiveCompare(host) == .orderedSame ? host : "\(source.name) · \(host)"
    }

    /// Asks, and gives the answer or why there is none.
    /// - Parameter isOwnHooks: recognises Yumi's own hooks in Antigravity's settings (`AntigravityHooks.isOwn`).
    static func ask(_ question: String, engine: Engine, depth: Depth, folder: String, english: Bool,
                    isOwnHooks: @escaping @Sendable (Any) -> Bool = { _ in false }) async throws -> Answer {
        let provider: any LLMProvider = switch engine {
        case .antigravity:
            AntigravityLLMProvider(folder: folder, model: depth.antigravityModel, isOwnHooks: isOwnHooks)
        case .claude:
            ClaudeCodeLLMProvider(binary: { ClaudeCLI.find() }, folder: folder, model: depth.claudeModel, readOnlyTools: ["WebSearch"])
        }
        let request = LLMRequest(system: instructions(for: engine, english: english),
                                 messages: [LLMMessage(role: .user, content: question)], expectsJSON: false, maxOutputTokens: 1500)
        return parse(try await provider.complete(request).text)
    }
}
