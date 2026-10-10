import SwiftUI

// « Recherche » in the rail: a question searched on the web by Gemini (Antigravity, on the
// person's Google account) or Claude (their subscription), each allowed the web search alone.
// A short answer, its sources as links. Nothing on the Mac is read or changed.

@MainActor
final class ResearchBoard: ObservableObject {
    static let shared = ResearchBoard()

    @Published var question = ""
    @Published private(set) var answer: WebResearch.Answer?
    @Published private(set) var asked: String?
    @Published private(set) var note: String?
    @Published private(set) var busy = false
    private var running: Task<Void, Never>?

    var engine: WebResearch.Engine { WebResearch.Engine.stored(antigravityInstalled: AntigravityLLMProvider.find() != nil) }
    var depth: WebResearch.Depth {
        UserDefaults.standard.string(forKey: WebResearch.Depth.key).flatMap(WebResearch.Depth.init(rawValue:)) ?? .quick
    }

    func search() {
        guard let text = question.nonEmptyTrimmed, !busy else { return }
        busy = true
        note = nil
        answer = nil
        asked = text
        let engine = engine, depth = depth
        let folder = AppIdentity.supportDirectory.appendingPathComponent("research").path
        running = Task {
            do {
                let found = try await WebResearch.ask(text, engine: engine, depth: depth, folder: folder, english: AppLanguage.isEnglish)
                if found.text.isEmpty { note = loc("Je n'ai rien trouvé de clair.") } else { answer = found }
                question = ""
            } catch LLMProviderError.unavailable {
                note = engine == .antigravity
                    ? loc("Antigravity n'est pas installé ou pas connecté (agy, puis connecte-toi).")
                    : loc("Claude Code n'est pas installé ou pas connecté (claude, puis /login).")
            } catch LLMProviderError.failed(let reason) {
                note = reason
            } catch is CancellationError {
                note = nil
            } catch {
                note = loc("La recherche n'a pas abouti.")
            }
            busy = false
        }
    }

    func stop() {
        running?.cancel()
        busy = false
    }

    func copy() {
        guard let answer else { return }
        let text = ([answer.text] + answer.sources.map { "\($0.name) : \($0.url.absoluteString)" }).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        note = loc("Copié.")
    }
}

struct ResearchActivity: View {
    @ObservedObject var board = ResearchBoard.shared
    @AppStorage(WebResearch.Engine.key) private var engineChoice = ""
    @AppStorage(WebResearch.Depth.key) private var depthChoice = WebResearch.Depth.quick.rawValue
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("", text: $board.question, prompt: Text("Que veux-tu savoir ?").foregroundStyle(IslandTheme.faint))
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .focused($focused)
                    .onSubmit { board.search() }
                    .disabled(board.busy)
                if board.busy {
                    RoundButton(symbol: "stop.fill", label: loc("Arrêter"), small: true) { board.stop() }
                } else {
                    RoundButton(style: .white, symbol: "magnifyingglass", label: loc("Chercher"), small: true) { board.search() }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(0)

            HStack(spacing: 10) {
                Menu {
                    ForEach(WebResearch.Engine.allCases, id: \.self) { engine in
                        Button(engine.label) { engineChoice = engine.rawValue }
                    }
                } label: { Text(board.engine.label).font(IslandTheme.text(11.5, .medium)).foregroundStyle(IslandTheme.muted) }
                .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(WebResearch.Depth.allCases, id: \.self) { depth in
                        Button(depth.label) { depthChoice = depth.rawValue }
                    }
                } label: { Text(board.depth.label).font(IslandTheme.text(11.5, .medium)).foregroundStyle(IslandTheme.muted) }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer()
            }
            .riseIn(1)

            if board.busy {
                ActSub(text: loc("Je cherche… « \(board.asked ?? "") »"))
            }
            if let answer = board.answer {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(WebResearch.displayed(answer.text))
                            .font(IslandTheme.text(13, .regular))
                            .foregroundStyle(IslandTheme.fg)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !answer.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(answer.sources, id: \.self) { source in
                                    Link(destination: source.url) {
                                        // The real site always shows: a name alone could say anything
                                        Label(WebResearch.label(source), systemImage: "link")
                                            .font(IslandTheme.text(11.5, .medium))
                                            .foregroundStyle(IslandTheme.blue)
                                            .lineLimit(1)
                                    }
                                    .help(source.url.absoluteString)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextButton(label: loc("Copier")) { board.copy() }
                    Spacer()
                }
            }
            if let note = board.note {
                Text(note).font(IslandTheme.text(12, .regular)).foregroundStyle(IslandTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }
}
