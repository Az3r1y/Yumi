import SwiftUI

// MARK: - The open island, in cards
//
// The tabs sit in the height of the menu bar, beside the notch; under them, the chips of the
// tab's modules, then the cards. Yumi is drawn above the island by IslandRootView, at the
// slot the view keeps for him (`YumiSlot`); a click on him opens the chat.

struct IslandOpenLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen
    /// The width, in content units (IslandOpenWidth).
    let width: CGFloat
    /// A tile and the sheet it grows into share their ground.
    @Namespace private var bento

    /// The top row takes the height of the notch, or of a menu bar without one.
    private var topHeight: CGFloat {
        let notch = model.layout.hasNotch ? model.layout.notchHeight / IslandConst.openScale : 0
        return max(28, notch)
    }

    /// The width the open island takes for a screen and a tab.
    static func widthKind(for screen: IslandScreen, category: ModuleCategory) -> IslandOpenWidth {
        switch screen {
        case .home, .module, .working:            return .tab(category)
        case .alert, .finished, .error:           return .alert
        case .settings:                           return .settings
        case .talk, .memory, .quickTask, .drop, .welcome: return .chat
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IslandTopBar(state: state, model: model, screen: screen, height: topHeight)

            content
                .id(contentID)

            // What Yumi says on his own: beside the activity, never in its place
            if let remark = model.remark(in: state) {
                RemarkLine(remark: remark, model: model)
                    .padding(.vertical, 7)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.islandSpring(0.42), value: model.remark(in: state)?.id)
        .frame(width: width, alignment: .topLeading)
        .foregroundStyle(IslandTheme.fg)
        .coordinateSpace(name: islandOpenSpace)
    }

    private var isTab: Bool { screen == .home || screen == .module || screen == .working }

    /// The module on screen in the tab, or the tasks.
    private var currentID: String? { model.current(in: model.category, modules: state.modules) }

    /// A new view plays `rise` again; what changes inside one does not.
    private var contentID: String {
        screen == .home ? "bento-\(model.category.rawValue)" : isTab ? "sheet-\(currentID ?? "")" : screen.rawValue
    }

    private var agent: ModuleSnapshot? { state.modules.first { $0.id == IslandModel.agentModuleID } }

    @ViewBuilder private var content: some View {
        switch screen {
        case .home, .module, .working:
            tab
        case .alert:
            HStack(alignment: .center, spacing: 10) {
                IslandCard(tint: IslandTheme.amber) {
                    HStack(spacing: 14) {
                        YumiSlot(width: 64)
                        AlertActivity(state: state, model: model)
                    }
                }
                let others = IslandSessions.rows(state.modules).filter { $0.state != .waiting }
                if !others.isEmpty { SessionColumn(rows: others) }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .finished:
            card(slot: 64, tint: IslandTheme.green) { FinishedActivity(state: state, model: model) }
        case .error:
            card(slot: 64, tint: IslandTheme.red) { ErrorActivity(state: state) }
        case .talk:
            card(slot: 44, top: true) { IslandTalkView(state: state) }
        case .settings:
            IslandCard {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        YumiSlot(width: 60)
                        TextButton(label: state.memory.isEmpty ? loc("Ce que Yumi sait de toi")
                                                               : loc("Ce que Yumi sait de toi (\(state.memory.count))")) {
                            IslandActions.go(.memory)
                        }
                    }
                    .frame(width: 104, alignment: .leading)
                    SettingsActivity(state: state)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .welcome:
            card(slot: 60) { WelcomeActivity() }
        case .memory:
            card(slot: 48, top: true) { MemoryActivity(state: state) }
        case .quickTask:
            card(slot: 48, top: true) { QuickTaskActivity() }
        case .drop:
            card(slot: 56) { DropActivity(state: state) }
        }
    }

    /// The tab: its bento, or the sheet of the tile that was opened.
    @ViewBuilder private var tab: some View {
        if screen == .home {
            IslandBento(state: state, model: model, namespace: bento)
        } else {
            sheet(currentID)
        }
    }

    /// A tile grown into its sheet: back to the bento on top, Yumi beside what the module says.
    private func sheet(_ id: String?) -> some View {
        let module = state.modules.first { $0.id == id }
        let color = module?.color ?? IslandTheme.violet
        return VStack(alignment: .leading, spacing: 10) {
            SheetHeader(name: module?.name ?? loc("À faire"), color: color)
            sheetBody(id: id, module: module)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            BentoSurface(color: color)
                .matchedGeometryEffect(id: "sheet-\(id ?? "")", in: bento)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func sheetBody(id: String?, module: ModuleSnapshot?) -> some View {
        if id == IslandModel.tasksID {
            HStack(alignment: .top, spacing: 14) { YumiSlot(width: 52); QuickTaskActivity() }
        } else if let module, module.id == IslandModel.agentModuleID, !module.rows.isEmpty {
            let chosen = module.rows.first { $0.id == model.selectedSessionID } ?? module.rows[0]
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    YumiSlot(width: 70)
                    SessionLive(row: chosen, journal: ClaudeSessionJournals.shared.journal(chosen.id))
                }
                HStack(spacing: 6) {
                    // The other sessions: a click shows theirs here, it does not leave Yumi
                    FlowLayout(spacing: 6) {
                        ForEach(module.rows.filter { $0.id != chosen.id }) { row in
                            SessionPill(row: row) {
                                withAnimation(.islandSpring(0.4)) { model.selectedSessionID = row.id }
                                IslandActions.tap()
                            }
                        }
                    }
                    if let action = chosen.action {
                        TextButton(label: loc("Ouvrir le terminal")) { IslandActions.row(IslandModel.agentModuleID, action) }
                            .fixedSize()
                    }
                }
            }
        } else if let module, module.id == IslandModel.agentModuleID, IslandModel.isBusy(state.effectiveState) {
            HStack(spacing: 14) { YumiSlot(width: 64); WorkingActivity(state: state, model: model) }
        } else if let module, module.id == "gmail" {
            HStack(alignment: .top, spacing: 14) { YumiSlot(width: 56); GmailSheet() }
        } else if let module, module.id == "focus" {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) { YumiSlot(width: 60); ModuleActivity(module: module) }
                FocusLengthPicker()
            }
        } else if let module {
            HStack(spacing: 14) { YumiSlot(width: 60); ModuleActivity(module: module) }
        } else {
            HStack(spacing: 14) {
                YumiSlot(width: 52)
                VStack(alignment: .leading, spacing: 3) {
                    ActTitle(text: loc("Je ne surveille rien pour l'instant."))
                    ActSub(text: loc("Choisis mes modules dans les réglages de l'app."))
                }
            }
        }
    }

    /// One card: Yumi on the left, the activity beside him.
    private func card<Inner: View>(slot: CGFloat, tint: Color? = nil, top: Bool = false,
                                   @ViewBuilder _ inner: () -> Inner) -> some View {
        let built = inner()
        return IslandCard(tint: tint) {
            HStack(alignment: top ? .top : .center, spacing: 14) {
                YumiSlot(width: slot)
                built.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Talk (`.act.chat`)

struct IslandTalkView: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    @State private var listHeight: CGFloat = 0
    /// The reader is at the bottom of the conversation: it follows what arrives.
    @State private var atBottom = true
    /// The text of the answer in progress, remembered as it grows. When the answer ends it
    /// stays on screen until the reply shows up in the history, so that the live answer
    /// becomes the final one without a blank in between.
    @State private var held: String?
    @FocusState private var focused: Bool

    /// The island grows with the conversation up to `IslandConst.openHeightMax`; past
    /// that, older lines scroll.
    private let listLimit: CGFloat = 190
    private static let bottomID = "bottom"

    private struct Line: Identifiable {
        let id: String
        let mine: Bool
        let text: String
        var engine: String? = nil
        var suggestions: [ChatSuggestion] = []
    }

    private var lines: [Line] {
        var out = state.chatHistory.map {
            Line(id: $0.id.uuidString, mine: $0.role == .user, text: $0.content, engine: $0.engine, suggestions: $0.suggestions)
        }
        if state.view == .note, let note = state.noteMessage {
            out.append(Line(id: "note", mine: false, text: note))
        }
        return out
    }

    /// The answer being made, or the text of the one that just ended and is not in the
    /// history yet.
    private var live: ChatLive? { state.chatLive ?? held.map { ChatLive(text: $0) } }

    private var contextName: String? {
        switch state.promptContext {
        case .file(let name, _):        return name
        case .window(let app, let title, _): return title.isEmpty ? app : title
        case nil:                       return nil
        }
    }

    var body: some View {
        let lines = lines
        VStack(alignment: .leading, spacing: 8) {
            if let contextName {
                // A control, not a label: one click detaches what is in front, one click attaches it again.
                Button { state.contextAttached.toggle() } label: {
                    ActMeta(color: state.contextAttached ? IslandTheme.violet : IslandTheme.muted,
                            text: state.contextAttached ? loc("Avec \(contextName)") : loc("Sans \(contextName) (cliquer pour joindre)"))
                        .opacity(state.contextAttached ? 1 : 0.6)
                }
                .buttonStyle(.plain)
                .help(state.contextAttached ? loc("Ne pas envoyer cette fenêtre avec ton message") : loc("Joindre cette fenêtre à ton message"))
                .accessibilityLabel(state.contextAttached ? loc("Contexte joint : \(contextName). Retirer") : loc("Contexte retiré : \(contextName). Joindre"))
                .riseIn(0)
            }

            if !lines.isEmpty || live != nil || state.stateOverride == .thinking {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(lines) { line in
                                VStack(alignment: .leading, spacing: 4) {
                                    ChatLine(text: line.text, mine: line.mine)
                                    // Only under the last answer: what Yumi offers now, not what he offered before.
                                    if !line.suggestions.isEmpty, line.id == lines.last?.id {
                                        ChatSuggestions(suggestions: line.suggestions, pick: pick)
                                    }
                                    if let engine = line.engine, !line.mine {
                                        Text(engine)
                                            .font(IslandTheme.text(9.5, .medium))
                                            .foregroundStyle(IslandTheme.faint)
                                            .accessibilityLabel(loc("Réponse de \(engine)"))
                                    }
                                }
                                .id(line.id)
                            }
                            if let live {
                                ChatLiveView(live: live, running: state.chatLive != nil)
                            } else if state.stateOverride == .thinking {
                                // The core has not started the live answer yet
                                ChatLiveView(live: ChatLive())
                            }
                            Color.clear.frame(height: 0).id(Self.bottomID)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            listHeight = height
                            if atBottom { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                        }
                    }
                    .frame(height: min(max(listHeight, 1), listLimit))
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        LiveChat.followsBottom(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                                               viewport: geometry.containerSize.height,
                                               content: geometry.contentSize.height)
                    } action: { _, follows in
                        atBottom = follows
                    }
                    .onChange(of: state.chatHistory.count) { _, _ in
                        // A message sent or received: back to the last line, and the answer
                        // that was held has its final place now
                        held = nil
                        atBottom = true
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                    .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
                .riseIn(1)
            }

            // `.ask`
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Demande-moi quelque chose").foregroundStyle(IslandTheme.faint))
                    // An unsent message keeps the island open when the person clicks elsewhere
                    .onChange(of: text) { _, value in IslandModel.shared.hasDraft = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .focused($focused)
                    .onSubmit(send)
                RoundButton(style: .white, symbol: "arrow.up", label: loc("Envoyer"), small: true, action: send)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: state.chatLive) { _, new in
            if let new {
                held = new.text.isEmpty ? nil : new.text
            } else if let kept = held {
                // If no reply ever lands in the history (an error), let go
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if state.chatLive == nil, held == kept { held = nil }
                }
            }
        }
        .onAppear {
            // A letter typed on the open island opened the chat: it is the start of the message
            if let seed = IslandModel.shared.chatSeed {
                text += seed
                IslandModel.shared.chatSeed = nil
            }
            focused = true
        }
    }

    private func send() {
        let query = text
        text = ""
        IslandActions.send(query)
        focused = true
    }

    /// A button of the simple mode: sends its sentence, or starts it in the field.
    private func pick(_ suggestion: ChatSuggestion) {
        if suggestion.sends {
            IslandActions.send(suggestion.text)
        } else {
            text = suggestion.text
            focused = true
        }
    }
}

/// The buttons the simple mode offers under its answer (Rappel, Tâche, Agenda, Minuteur, Musique).
struct ChatSuggestions: View {
    let suggestions: [ChatSuggestion]
    let pick: (ChatSuggestion) -> Void
    @Environment(\.islandAccent) private var accent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(suggestions) { suggestion in
                    Button { pick(suggestion) } label: {
                        Text(suggestion.label)
                            .font(IslandTheme.text(11, .medium))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .overlay(Capsule().strokeBorder(accent.opacity(0.8), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
