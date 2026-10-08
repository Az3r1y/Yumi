import SwiftUI

// MARK: - The open island (`.open` in design/yumi/maquette/reference.html, version 13)
//
// One activity at a time, each with its own layout, then the rail that is always there.
// Yumi sits on the left (he is drawn above the island by IslandRootView, not here); a
// click on him opens the chat.

struct IslandOpenLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen

    /// The module the screen is about: the one chosen in the rail, or the agent's.
    private var module: ModuleSnapshot? {
        switch screen {
        case .module: return model.selectedModule(in: state.modules)
        case .working, .alert, .finished, .error:
            return state.modules.first { $0.id == IslandModel.agentModuleID }
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // `.act { grid-template-columns: 92px 1fr auto; gap: 0 14px; padding: 18px 22px 8px 0; min-height: 102px }`
            HStack(alignment: .center, spacing: wide ? 6 : 14) {
                // Yumi's place
                Color.clear
                    .frame(width: IslandConst.seatColumn)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { IslandActions.pokeYumi(talking: screen == .talk) }

                activity
                    .id(activityID)
                    .frame(maxWidth: .infinity, alignment: screen == .talk ? .topLeading : .leading)
            }
            .frame(minHeight: IslandConst.actMinHeight)
            .padding(.top, (wide ? 14 : IslandConst.openPaddingTop) + model.layout.openInset / IslandConst.openScale)
            .padding(.trailing, wide ? 14 : IslandConst.openPaddingTrailing)
            .padding(.bottom, IslandConst.openPaddingBottom)

            // What Yumi says on his own: beside the activity, never in its place
            if let remark = model.remark(in: state) {
                RemarkLine(remark: remark, model: model)
                    .padding(.vertical, 7)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            IslandRail(state: state, model: model, screen: screen, moduleID: module?.id)
        }
        .animation(.islandSpring(0.42), value: model.remark(in: state)?.id)
        .frame(width: IslandConst.expandedWidth)
        .foregroundStyle(IslandTheme.fg)
    }

    /// `.act.wide`: the overview and the settings use the whole width.
    private var wide: Bool { screen == .home || screen == .settings || screen == .memory || screen == .quickTask }

    /// A new activity plays `rise` again; what changes inside one does not.
    private var activityID: String {
        screen == .module ? "module-\(module?.id ?? "")" : screen.rawValue
    }

    @ViewBuilder private var activity: some View {
        switch screen {
        case .home:     OverviewActivity(state: state)
        case .working:  WorkingActivity(state: state, model: model)
        case .alert:    AlertActivity(state: state, model: model)
        case .finished: FinishedActivity(state: state, model: model)
        case .error:    ErrorActivity(state: state)
        case .talk:     IslandTalkView(state: state)
        case .settings: SettingsActivity(state: state)
        case .welcome:  WelcomeActivity()
        case .memory:   MemoryActivity(state: state)
        case .quickTask: QuickTaskActivity()
        case .drop:     DropActivity(state: state)
        case .module:
            if let module {
                ModuleActivity(module: module)
            } else {
                OverviewActivity(state: state)
            }
        }
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
    }

    private var lines: [Line] {
        var out = state.chatHistory.map { Line(id: $0.id.uuidString, mine: $0.role == .user, text: $0.content) }
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
                                ChatLine(text: line.text, mine: line.mine).id(line.id)
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
        .onAppear { focused = true }
    }

    private func send() {
        let query = text
        text = ""
        IslandActions.send(query)
        focused = true
    }
}
