import SwiftUI

// MARK: - The open island (`.open` in design/yumi/maquette/reference.html)
//
// 480 wide, as low as the content allows. Yumi sits on the left with a few words under him
// (he is drawn above the island by IslandRootView, not here), one piece of information on
// his right, three buttons (home, talk, drop), then the row of modules.

struct IslandOpenLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen

    var body: some View {
        let card = IslandContent.card(for: screen, state: state, model: model)

        VStack(spacing: 0) {
            // `.o-top { grid-template-columns: 96px 1fr 30px; gap: 0 8px; padding: 8px 10px 7px 0 }`
            HStack(alignment: .top, spacing: 12) {
                seat(caption: model.habit.map(IslandModel.caption(for:)) ?? card.caption)

                Group {
                    switch screen {
                    case .talk: IslandTalkView(state: state)
                    case .drop: IslandDropView(state: state)
                    default:    IslandCardView(card: card)
                    }
                }
                .id(blockID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                tabs
                    .frame(width: 30)
                    .frame(maxHeight: .infinity)
            }
            .padding(.top, IslandConst.openPaddingTop + model.layout.openInset / IslandConst.openScale)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.bottom, IslandConst.openPaddingBottom)

            IslandDock(state: state, model: model, screen: screen)
        }
        .frame(width: IslandConst.expandedWidth)
        .foregroundStyle(IslandTheme.fg)
    }

    /// A new block plays `rise` again; a title that changes inside the same view does not.
    private var blockID: String {
        screen == .module ? "module-\(model.selectedModuleID ?? "")" : screen.rawValue
    }

    /// `.o-seat`: 82 high, the caption at the bottom. A click on Yumi makes him bounce.
    private func seat(caption: String) -> some View {
        Text(caption)
            .font(IslandTheme.round(10.5, .semibold))
            .foregroundStyle(IslandTheme.muted)
            .lineLimit(1)
            .fixedSize()
            .frame(width: IslandConst.seatColumn, height: IslandConst.seatHeight, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                SoundEngine.shared.play("pop")
                model.pose(.boing)
            }
    }

    /// `.o-tabs`: home, talk, drop
    private var tabs: some View {
        VStack(spacing: 2) {
            IslandTab(glyph: .home, label: "Accueil", on: state.view == .overview || state.view == .empty) {
                IslandActions.go(.overview)
            }
            IslandTab(glyph: .chat, label: "Parler", on: screen == .talk) {
                IslandActions.go(.prompt)
            }
            IslandTab(glyph: .plus, label: "Déposer", on: screen == .drop) {
                IslandActions.go(.upload)
            }
        }
    }
}

/// `.ib`
struct IslandTab: View {
    let glyph: IslandGlyph
    let label: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            IslandGlyphView(glyph: glyph)
                .foregroundStyle(on || hover ? IslandTheme.fg : IslandTheme.muted)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(on ? IslandTheme.surface : (hover ? Color.white.opacity(0.07) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - One piece of information (`.blk`)

struct IslandCardView: View {
    let card: IslandCard

    var body: some View {
        VStack(alignment: .leading, spacing: IslandConst.lineGap) {
            Text(card.eyebrow)
                .font(IslandTheme.round(10, .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(card.color)
                .lineLimit(1)
                .riseIn(0)

            Text(card.title)
                .font(IslandTheme.round(17, .heavy))
                .tracking(-0.17)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .riseIn(1)

            Group {
                if let code = card.code {
                    IslandCode(text: code)
                } else {
                    Text(card.sub ?? "")
                        .font(IslandTheme.text(12.5))
                        .foregroundStyle(IslandTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .riseIn(2)

            IslandButtonRow(actions: card.actions, main: card.main, color: card.color)
                .riseIn(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.code`
struct IslandCode: View {
    let text: String

    var body: some View {
        Text(text)
            .font(IslandTheme.mono(11.5))
            .foregroundStyle(IslandTheme.code)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(IslandTheme.surface))
    }
}

/// `.row`
struct IslandButtonRow: View {
    let actions: [IslandAction]
    var main: Int?
    var color: Color = IslandTheme.fg
    var enabled: (IslandAction) -> Bool = { _ in true }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                IslandButton(label: action.label, main: index == main, color: color,
                             enabled: enabled(action), action: action.run)
            }
        }
        .padding(.top, 4)
    }
}

/// `.btn`, and `.btn.main` in the colour of the card
struct IslandButton: View {
    let label: String
    var main = false
    var color: Color = IslandTheme.fg
    var enabled = true
    let action: @MainActor () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { action() }) {
            Text(label)
                .font(IslandTheme.round(12, .bold))
                .lineLimit(1)
                .foregroundStyle(main ? IslandTheme.ink : IslandTheme.fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(main ? color : (hover ? IslandTheme.raise : IslandTheme.surface)))
                .overlay(Capsule().strokeBorder(IslandTheme.line, lineWidth: main ? 0 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(IslandPress())
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

/// `.btn:active { transform: scale(.94) }`, `transition: transform .12s`
struct IslandPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.islandEase(0.12), value: configuration.isPressed)
    }
}

// MARK: - Talk (`c.chat`)

struct IslandTalkView: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    @State private var listHeight: CGFloat = 0
    @FocusState private var focused: Bool

    /// The island never grows past `IslandConst.openHeightMax`: older lines scroll.
    private let listLimit: CGFloat = 132

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
        if out.isEmpty { out.append(Line(id: "hello", mine: false, text: "Je t'écoute.")) }
        if state.stateOverride == .thinking { out.append(Line(id: "typing", mine: false, text: "…")) }
        return out
    }

    private var contextName: String? {
        switch state.promptContext {
        case .file(let name, _):        return name
        case .window(let app, let title, _): return title.isEmpty ? app : title
        case nil:                       return nil
        }
    }

    var body: some View {
        let lines = lines
        VStack(alignment: .leading, spacing: IslandConst.lineGap) {
            if let contextName {
                Text("Avec \(contextName)")
                    .font(IslandTheme.round(10, .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(IslandTheme.violet)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .riseIn(0)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(lines) { line in
                            bubble(line).id(line.id)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(max(listHeight, 1), listLimit))
                .onChange(of: lines.last?.id) { _, last in
                    if let last { withAnimation(.islandEase(0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
                }
                .onAppear {
                    if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .riseIn(1)

            // `.field`
            TextField("", text: $text, prompt: Text("Demande quelque chose à Yumi").foregroundStyle(IslandTheme.faint))
                .textFieldStyle(.plain)
                .font(IslandTheme.text(12.5))
                .foregroundStyle(IslandTheme.fg)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(IslandTheme.surface))
                .overlay(Capsule().strokeBorder(IslandTheme.line, lineWidth: 1))
                .riseIn(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }

    /// `.bub`, and `.bub.me` on the right
    private func bubble(_ line: Line) -> some View {
        HStack(spacing: 0) {
            if line.mine { Spacer(minLength: 16) }
            Text(line.text)
                .font(IslandTheme.text(12))
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 13).fill(line.mine ? IslandTheme.bubbleMe : IslandTheme.surface))
            if !line.mine { Spacer(minLength: 16) }
        }
    }

    private func send() {
        let query = text
        text = ""
        IslandActions.send(query)
        focused = true
    }
}

// MARK: - Drop (`c.drop`)

struct IslandDropView: View {
    @ObservedObject var state: AppState

    private var file: DroppedFile? { state.view == .upload ? nil : state.droppedFile }

    var body: some View {
        let actions = [
            IslandAction("Résumer") { IslandActions.summarize() },
            IslandAction("Envoyer") { IslandActions.sendByMail() },
            IslandAction("Ranger") { IslandActions.putAway() },
        ]
        // `.drop { border: 1.5px dashed rgba(255,255,255,.22); border-radius: 14px; padding: 9px 12px; gap: 4px }`
        VStack(alignment: .leading, spacing: IslandConst.lineGap) {
            Text(file.map { "\($0.name), j'en fais quoi ?" } ?? "Dépose ici, je m'en occupe")
                .font(IslandTheme.round(17, .heavy))
                .tracking(-0.17)
                .lineLimit(1)
                .truncationMode(.middle)
            // Without a file, only "Résumer" has something to work on: the window in front
            IslandButtonRow(actions: actions, main: nil) { action in
                file != nil || action.label == "Résumer"
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(state.fileDragOver ? 0.5 : 0.22),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .riseIn(0)
    }
}
