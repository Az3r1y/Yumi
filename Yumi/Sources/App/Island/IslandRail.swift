import SwiftUI

// The rail at the bottom of the open island, always there (`.rail` in the mock-up): the
// overview, one icon per module, then the chat and the settings. The one on screen opens
// into its name; a dot marks what is live; hovering shows the name in a label.

struct IslandRail: View {
    /// The App Store build may not launch Antigravity nor Claude Code.
    private static var canSearch: Bool {
        #if APPSTORE
        false
        #else
        true
        #endif
    }

    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen
    /// The module on screen, if the screen is about one.
    let moduleID: String?

    var body: some View {
        HStack(spacing: 1) {
            RailButton(symbol: "square.grid.2x2.fill", name: loc("Tous"), label: loc("Tous les modules"),
                       color: .white, on: screen == .home) {
                IslandActions.go(.overview)
            }
            ForEach(state.modules.prefix(ModuleCatalog.selectionLimit)) { module in
                RailButton(symbol: module.glyph, name: module.name, label: module.name,
                           color: module.color, on: module.id == moduleID, live: module.live != nil) {
                    IslandActions.showModule(module.id)
                }
            }
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 3)
            RailButton(symbol: "bubble.left", name: loc("Parler"), label: loc("Parler à Yumi"),
                       color: IslandTheme.violet, on: screen == .talk, bright: true) {
                IslandActions.go(.prompt)
            }
            // The App Store build may not launch Antigravity nor Claude Code
            if Self.canSearch, Feature.isOn(.research) {
                RailButton(symbol: "magnifyingglass", name: loc("Recherche"), label: loc("Chercher sur le web"),
                           color: .white, on: screen == .research) {
                    IslandActions.go(.research)
                }
            }
            RailButton(symbol: "textformat.abc", name: loc("Texte"), label: loc("Corriger ou traduire un texte"),
                       color: .white, on: screen == .textTool) {
                TextToolBoard.shared.openedByHand()
                IslandActions.go(.textTool)
            }
            RailButton(symbol: "gearshape", name: loc("Réglages"), label: loc("Réglages"),
                       color: .white, on: screen == .settings) {
                IslandActions.go(.settings)
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 10)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity)
    }
}

/// `.rail button`
private struct RailButton: View {
    let symbol: String
    let name: String
    let label: String
    let color: Color
    let on: Bool
    var live = false
    /// The chat icon stays white.
    var bright = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(on ? color : (bright || hover ? Color.white : IslandTheme.faint))
                    .frame(width: 14, height: 14)
                if on {
                    Text(name)
                        .font(IslandTheme.text(11, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.leading, on ? 8 : 4)
            .padding(.trailing, on ? 10 : 4)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(on ? 0.13 : (hover ? 0.08 : 0))))
            .overlay(alignment: .topTrailing) {
                if live && !on {
                    Circle().fill(color).frame(width: 5, height: 5).offset(x: -3, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        // The name in a label above, while the pointer is on an icon that does not show it
        .overlay(alignment: .top) {
            if hover && !on {
                Text(label)
                    .font(IslandTheme.text(10.5, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#20232F")))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .offset(y: -25)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(.islandEase(0.15), value: hover)
        .animation(.islandSpring(0.35), value: on)
        .accessibilityLabel(label)
        .zIndex(hover ? 1 : 0)
    }
}

// MARK: - The overview ("Tous"): every module on two columns

/// The modules, in the person's order. A module is dragged onto another to take its place.
/// "Modifier" works like the iPhone's home screen: the tiles wiggle, each can be hidden, and
/// the hidden ones come back with their plus. The same list as Settings, Modules (ModuleLineup).
struct OverviewActivity: View {
    @ObservedObject var state: AppState
    @ObservedObject private var lineup = ModuleLineup.shared
    @ObservedObject private var model = IslandModel.shared
    @State private var dragged: String?

    private struct Tile: Identifiable {
        let module: ModuleSnapshot
        let shown: Bool
        var id: String { module.id }
    }

    private var tiles: [Tile] {
        let live = Dictionary(state.modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if model.editingModules {
            return lineup.entries.map { Tile(module: live[$0.id] ?? $0.snapshot, shown: $0.selected) }
        }
        return state.modules.prefix(ModuleCatalog.selectionLimit).map { Tile(module: $0, shown: true) }
    }

    var body: some View {
        let tiles = tiles
        VStack(alignment: .leading, spacing: 6) {
            if tiles.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ActTitle(text: loc("Je ne surveille rien pour l'instant."))
                    ActSub(text: loc("Choisis mes modules dans les réglages de l'app."))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                grid(tiles)
            }
            HStack {
                if model.editingModules {
                    ActSub(text: loc("Glisse pour changer l'ordre. Les \(ModuleCatalog.pinnedLimit) premiers restent dans l'île."))
                }
                Spacer(minLength: 0)
                TextButton(label: model.editingModules ? loc("OK") : loc("Modifier")) {
                    withAnimation(.islandSpring(0.35)) { model.editingModules.toggle() }
                }
            }
        }
        .onDisappear { model.editingModules = false }
    }

    private func grid(_ tiles: [Tile]) -> some View {
        // `.ovr { grid-template-columns: 1.3fr 1fr; gap: 1px 8px }`
        GeometryReader { geo in
            let first = (geo.size.width - 8) * 1.3 / 2.3
            let rows = stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        tile(row[0]).frame(width: first)
                        if row.count > 1 { tile(row[1]) } else { Spacer(minLength: 0) }
                    }
                    .riseIn(index, stagger: 0.03)
                }
            }
        }
        .frame(height: CGFloat((tiles.count + 1) / 2) * OverviewRow.height + CGFloat(max(0, (tiles.count + 1) / 2 - 1)))
        .animation(.islandSpring(0.35), value: tiles.map(\.id))
    }

    private func tile(_ tile: Tile) -> some View {
        OverviewRow(module: tile.module, editing: model.editingModules, shown: tile.shown,
                    place: lineup.place(of: tile.id)) { shown in
            lineup.setShown(tile.id, shown)
        }
        .opacity(dragged == tile.id ? 0.4 : 1)
        .onDrag {
            dragged = tile.id
            return NSItemProvider(object: tile.id as NSString)
        }
        .onDrop(of: [.text], delegate: TileDrop(target: tile.id, dragged: $dragged, lineup: lineup))
    }
}

/// Dragging a tile over another puts it in that one's place, right away.
private struct TileDrop: DropDelegate {
    let target: String
    @Binding var dragged: String?
    let lineup: ModuleLineup

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        MainActor.assumeIsolated {
            guard let index = lineup.selected.firstIndex(where: { $0.id == target }) else { return }
            if lineup.place(of: dragged) == .hidden { lineup.setShown(dragged, true) }
            lineup.move(dragged, to: index)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

/// `.orow`: icon, full name, key figure. In edit mode it wiggles, with a minus to hide it or,
/// when hidden, a plus to show it again.
private struct OverviewRow: View {
    static let height: CGFloat = 23
    let module: ModuleSnapshot
    var editing = false
    var shown = true
    var place: ModuleLineup.Place = .island
    var setShown: (Bool) -> Void = { _ in }
    @State private var hover = false
    @State private var wiggle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: { if !editing { IslandActions.showModule(module.id) } }) {
            HStack(spacing: 7) {
                if editing {
                    Button { setShown(!shown) } label: {
                        Image(systemName: shown ? "minus.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(shown ? IslandTheme.red : IslandTheme.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shown ? loc("Masquer \(module.name)") : loc("Afficher \(module.name)"))
                }
                Image(systemName: module.glyph)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(module.color)
                    .frame(width: 15, height: 14)
                Text(module.name)
                    .font(IslandTheme.text(12, .medium))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if editing {
                    Text(place == .island ? loc("île") : place == .secondSquare ? loc("second carré") : loc("masqué"))
                        .font(IslandTheme.text(10, .medium))
                        .foregroundStyle(IslandTheme.faint)
                        .lineLimit(1)
                } else {
                    Text(module.status)
                        .font(IslandTheme.round(11.5, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(module.color)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover || editing ? 0.09 : 0)))
            .opacity(shown ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .rotationEffect(.degrees(editing && wiggle && !reduceMotion ? 0.8 : editing && !reduceMotion ? -0.8 : 0))
        .onChange(of: editing, initial: true) { _, on in
            guard on, !reduceMotion else { wiggle = false; return }
            withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true).delay(Double(abs(module.id.hashValue % 7)) * 0.02)) {
                wiggle = true
            }
        }
    }
}
