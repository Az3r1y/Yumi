import SwiftUI

// Correct or translate a text (Réglages > Général, ⌥T by default, or « Texte » in the rail):
// the text selected in the app in front comes in; Apple Intelligence's model corrects or
// translates it on the Mac (or, without it, macOS's spelling checker and Apple's translation);
// the result is shown with what changed, and nothing changes in the app before « Remplacer ».
// Escape folds the island.

@MainActor
final class TextToolBoard: ObservableObject {
    static let shared = TextToolBoard()

    enum Mode: Equatable { case correct, translate, summary, tone(TextAI.Tone), reply, event }

    @Published var source = "" { didSet { if source != oldValue { clearResult() } } }
    @Published var target: TextLanguage = .en
    @Published private(set) var mode: Mode?
    @Published private(set) var fixes: [TextFix] = []
    /// The fixes the person keeps, by id. All of them at first.
    @Published var kept: Set<Int> = []
    @Published private(set) var translation: String?
    /// The text corrected by Apple Intelligence; nil when the spelling checker did the work.
    @Published private(set) var corrected: String?
    /// A summary, a rewriting or a reply by Apple Intelligence.
    @Published private(set) var generated: String?
    /// A reminder or an appointment found in the text, to add after the person's approval.
    @Published private(set) var event: TextEvent?
    @Published private(set) var note: String?
    @Published private(set) var busy = false
    /// Where the text came from: replacing puts the result there.
    @Published private(set) var origin: String?
    private var selection: TextSelection?

    /// Reads the selection of the app in front, before the island takes the keyboard.
    func grabSelection() {
        selection = TextSelection.current()
        origin = selection?.appName.nonEmptyTrimmed
        source = selection?.text ?? ""
        clearResult()
        note = selection == nil ? loc("Rien de sélectionné : colle ton texte ici.") : nil
        target = TextLanguage.target(for: TextCorrector.language(of: source))
    }

    /// The text of a dropped image, read on the Mac, ready to correct, translate or sum up.
    func read(image url: URL) {
        selection = nil
        origin = nil
        source = ""
        note = loc("Je lis l'image…")
        IslandActions.go(.textTool)
        Task {
            if let text = await ImageText.read(url) {
                source = text
                note = nil
                target = TextLanguage.target(for: TextCorrector.language(of: text))
            } else {
                note = loc("Je ne vois pas de texte dans cette image.")
            }
        }
    }

    /// Opened from the rail: the text stays, the app it came from is forgotten.
    func openedByHand() {
        selection = nil
        origin = nil
        note = nil
    }

    func correct() {
        guard source.nonEmptyTrimmed != nil, !busy else { return }
        mode = .correct
        translation = nil
        corrected = nil
        fixes = []
        note = nil
        guard TextAI.isAvailable else { return spellCheck() }
        busy = true
        let text = source
        Task {
            do throws(TextAI.Failure) {
                let result = try await TextAI.correct(text)
                guard source == text else { busy = false; return }
                if result == text { note = loc("Je ne vois rien à corriger.") } else { corrected = result }
            } catch {
                // Apple Intelligence could not: the spelling checker, at least
                spellCheck()
            }
            busy = false
        }
    }

    /// macOS's spelling checker: typos and accents, each fix to keep or leave out.
    private func spellCheck() {
        fixes = TextCorrector.fixes(for: source)
        kept = Set(fixes.map(\.id))
        note = fixes.isEmpty ? loc("Je ne vois pas de faute d'orthographe. La grammaire, je ne la vérifie pas.") : nil
    }

    func translate() {
        guard source.nonEmptyTrimmed != nil, !busy else { return }
        mode = .translate
        fixes = []
        translation = nil
        busy = true
        note = nil
        let text = source, target = target
        Task {
            if TextAI.isAvailable, let done = try? await TextAI.translate(text, to: target) {
                translation = done
            } else {
                // Without Apple Intelligence, or when it could not: Apple's translation
                do throws(TextTranslator.Failure) {
                    translation = try await TextTranslator.translate(text, from: TextCorrector.language(of: text), to: target)
                } catch {
                    note = error.reason
                }
            }
            busy = false
        }
    }

    // MARK: Apple Intelligence

    /// Summary, tone and reply: the model's answer, shown before anything is replaced.
    func generate(_ mode: Mode) {
        guard source.nonEmptyTrimmed != nil, !busy else { return }
        clearResult()
        self.mode = mode
        busy = true
        note = nil
        let text = source
        Task {
            do throws(TextAI.Failure) {
                let answer: String
                switch mode {
                case .summary: answer = try await TextAI.summarize(text)
                case .tone(let tone): answer = try await TextAI.rewrite(text, tone: tone)
                default: answer = try await TextAI.reply(to: text)
                }
                if source == text { generated = answer }
            } catch {
                note = error == .unavailable ? loc("Il faut Apple Intelligence pour ça.") : loc("Je n'ai pas réussi, réessaie.")
            }
            busy = false
        }
    }

    func findEvent() {
        guard source.nonEmptyTrimmed != nil, !busy else { return }
        clearResult()
        mode = .event
        busy = true
        note = nil
        let text = source
        Task {
            event = await TextEvent.find(in: text)
            if event == nil { note = loc("Je ne trouve rien à mettre dans l'agenda ou les rappels.") }
            busy = false
        }
    }

    /// Through the agent: its approval, its write, its check.
    func addEvent() {
        guard let event, let agent = AppState.shared.agent else { return }
        busy = true
        Task {
            let (plan, request) = event.plan()
            let result = await agent.execute(plan, for: request)
            busy = false
            // The approval took the island: come back to the text
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.textTool)
            note = result.status.succeeded ? loc("C'est ajouté.") : loc("Pas ajouté.")
            if result.status.succeeded { self.event = nil }
        }
    }

    /// What would replace the selection: the text with the kept fixes, the translation, or what
    /// Apple Intelligence wrote.
    var output: String? {
        switch mode {
        case .correct: corrected ?? (fixes.isEmpty ? nil : TextCorrector.apply(fixes.filter { kept.contains($0.id) }, to: source))
        case .translate: translation
        case .summary, .tone, .reply: generated
        case .event, nil: nil
        }
    }

    /// A summary or a reply goes beside the text, never in its place: only copied.
    var canReplace: Bool { selection != nil && output != nil && mode != .summary && mode != .reply }

    func replace() {
        guard let output, let selection else { return }
        if selection.replace(with: output) {
            note = loc("C'est remplacé dans \(selection.appName).")
            self.selection = nil
            origin = nil
        } else {
            copy()
            note = loc("\(selection.appName) n'a pas voulu que je remplace : c'est copié, colle-le avec ⌘V.")
        }
    }

    func copy() {
        guard let output else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        note = loc("Copié.")
    }

    private func clearResult() {
        mode = nil
        fixes = []
        kept = []
        translation = nil
        corrected = nil
        generated = nil
        event = nil
    }
}

struct TextToolActivity: View {
    @ObservedObject var board = TextToolBoard.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActSub(text: board.origin.map { loc("Sélection de \($0)") } ?? loc("Corriger ou traduire un texte")).riseIn(0)

            TextEditor(text: $board.source)
                .scrollContentBackground(.hidden)
                .font(IslandTheme.text(13, .regular))
                .foregroundStyle(IslandTheme.fg)
                .focused($focused)
                .frame(minHeight: 46, maxHeight: 96)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                .riseIn(1)

            HStack(spacing: 6) {
                Pill(label: loc("Corriger"), symbol: "checkmark.circle", on: board.mode == .correct) { board.correct() }
                Pill(label: loc("Traduire"), symbol: "character.bubble", on: board.mode == .translate) { board.translate() }
                Menu {
                    ForEach(TextLanguage.allCases) { language in
                        Button(language.name) {
                            board.target = language
                            if board.mode == .translate { board.translate() }
                        }
                    }
                } label: {
                    Text(loc("en \(AppLanguage.isEnglish ? board.target.name : board.target.name.lowercased())"))
                        .font(IslandTheme.text(12, .medium))
                        .foregroundStyle(IslandTheme.muted)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .riseIn(2)

            if TextAI.isAvailable, !writingTools.isEmpty {
                HStack(spacing: 6) {
                    if writingTools.contains(.textSummary) {
                        Pill(label: loc("Résumer"), symbol: "text.append", on: board.mode == .summary) { board.generate(.summary) }
                    }
                    if writingTools.contains(.textTone) {
                        Menu {
                            ForEach(TextAI.Tone.allCases) { tone in Button(tone.name) { board.generate(.tone(tone)) } }
                        } label: {
                            Label(loc("Ton"), systemImage: "theatermasks").font(IslandTheme.text(12, .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    if writingTools.contains(.textReply) {
                        Pill(label: loc("Répondre"), symbol: "arrowshape.turn.up.left", on: board.mode == .reply) { board.generate(.reply) }
                    }
                    if writingTools.contains(.textToEvent) {
                        Pill(label: loc("Agenda"), symbol: "calendar.badge.plus", on: board.mode == .event) { board.findEvent() }
                    }
                    Spacer()
                }
                .riseIn(3)
            }

            result
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = board.source.isEmpty }
    }

    /// The Apple Intelligence actions the person kept (Réglages › Fonctions).
    private var writingTools: [Feature] {
        [.textSummary, .textTone, .textReply, .textToEvent].filter { Feature.isOn($0) }
    }

    @ViewBuilder private var result: some View {
        if board.busy {
            ActSub(text: board.mode == .translate ? loc("Je traduis…") : board.mode == .correct ? loc("Je corrige…") : loc("Je réfléchis…"))
        }
        if let generated = board.generated {
            ScrollView(.vertical, showsIndicators: false) {
                Text(generated)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let event = board.event {
            HStack(spacing: 8) {
                Image(systemName: event.isAppointment ? "calendar" : "checklist")
                    .foregroundStyle(IslandTheme.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(IslandTheme.text(13, .semibold)).foregroundStyle(IslandTheme.fg)
                    Text(describe(event)).font(IslandTheme.text(11.5, .regular)).foregroundStyle(IslandTheme.muted)
                }
                Spacer()
                Pill(label: loc("Ajouter"), symbol: "plus", on: true, strong: true) { board.addEvent() }
            }
        }
        if board.mode == .correct, let corrected = board.corrected {
            // What changed, in green: read before replacing
            ScrollView(.vertical, showsIndicators: false) {
                TextDiff.words(from: board.source, to: corrected).reduce(Text("")) { line, word in
                    line + Text(word.text).foregroundColor(word.changed ? IslandTheme.green : IslandTheme.fg)
                        .fontWeight(word.changed ? .semibold : .regular)
                }
                .font(IslandTheme.text(13, .regular))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
            .fixedSize(horizontal: false, vertical: true)
        }
        if board.mode == .correct, !board.fixes.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(board.fixes) { fix in fixLine(fix) }
                }
            }
            .frame(maxHeight: 96)
            .fixedSize(horizontal: false, vertical: board.fixes.count <= 4)
        }
        if board.mode == .translate, let translation = board.translation {
            ScrollView(.vertical, showsIndicators: false) {
                Text(translation)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let note = board.note {
            Text(note)
                .font(IslandTheme.text(12, .regular))
                .foregroundStyle(IslandTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if board.output != nil {
            HStack(spacing: 6) {
                if board.canReplace {
                    Pill(label: loc("Remplacer"), symbol: "arrow.left.arrow.right", on: true, strong: true) { board.replace() }
                }
                Pill(label: loc("Copier"), symbol: "doc.on.doc", on: false) { board.copy() }
                Spacer()
            }
        }
    }

    /// "Événement · jeudi 8 octobre à 15:00", "Rappel · sans date".
    private func describe(_ event: TextEvent) -> String {
        let kind = event.isAppointment ? loc("Événement") : loc("Rappel")
        guard let day = event.date, let date = ISO8601DateFormatter().date(from: day + "T12:00:00Z") else { return kind + " · " + loc("sans date") }
        var when = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))
        if let time = event.time { when += " " + loc("à \(time)") }
        return kind + " · " + when
    }

    private func fixLine(_ fix: TextFix) -> some View {
        let kept = board.kept.contains(fix.id)
        return Button {
            if kept { board.kept.remove(fix.id) } else { board.kept.insert(fix.id) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(kept ? IslandTheme.green : IslandTheme.faint)
                Text(fix.original).strikethrough().foregroundStyle(IslandTheme.muted)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandTheme.faint)
                Text(fix.replacement).foregroundStyle(kept ? IslandTheme.fg : IslandTheme.muted)
                Spacer()
            }
            .font(IslandTheme.text(12, .semibold))
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kept ? loc("Garder « \(fix.replacement) »") : loc("Laisser « \(fix.original) »"))
    }
}

/// A rounded button with a word: what the text screen does.
private struct Pill: View {
    let label: String
    let symbol: String
    let on: Bool
    var strong = false
    let action: @MainActor () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { action() }) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(IslandTheme.text(12, .semibold))
            }
            .foregroundStyle(strong ? IslandTheme.ink : IslandTheme.fg)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(strong ? Color.white : Color.white.opacity(on || hover ? 0.18 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
