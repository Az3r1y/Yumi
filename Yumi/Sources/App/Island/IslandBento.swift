import SwiftUI

// The open island's home, per tab (the bento of the island demo): Yumi sits in the large tile
// with the tab's lead module, the other modules fill the tiles beside it. A click on a tile
// makes it grow into its sheet; Yumi comes along and sits in the sheet.

/// The modules of a tab in tiles. The lead takes the large tile and Yumi with it.
struct IslandBento: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let namespace: Namespace.ID

    /// The large tile: the module that says most about the tab, else the person's first one.
    static func lead(of ids: [String]) -> String? {
        for preferred in ["claude-code", "agenda", "music", "musique"] where ids.contains(preferred) { return preferred }
        return ids.first
    }

    /// Height of a small tile; the large one is two of them and the gap.
    static let row: CGFloat = 88
    static let gap: CGFloat = 8

    var body: some View {
        let ids = model.entries(in: model.category, modules: state.modules)
        let lead = Self.lead(of: ids)
        let others = ids.filter { $0 != lead }
        let big = Self.row * 2 + Self.gap
        HStack(alignment: .top, spacing: Self.gap) {
            if let lead {
                tile(lead, index: 0, lead: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: big)
            } else {
                YumiTile().frame(maxWidth: .infinity).frame(height: big)
            }
            if !others.isEmpty {
                side(others)
                    .frame(maxWidth: .infinity)
                    .frame(height: big)
            }
        }
    }

    /// The tiles beside the large one: one fills the column, two stack, three put the first
    /// across the top, four make a square; more go on as small tiles in pairs.
    @ViewBuilder private func side(_ ids: [String]) -> some View {
        switch ids.count {
        case 1:
            tile(ids[0], index: 1)
        case 2:
            VStack(spacing: Self.gap) { tile(ids[0], index: 1); tile(ids[1], index: 2) }
        case 3:
            VStack(spacing: Self.gap) {
                tile(ids[0], index: 1)
                HStack(spacing: Self.gap) { tile(ids[1], index: 2); tile(ids[2], index: 3) }
            }
        default:
            let pairs = stride(from: 0, to: ids.count, by: 2).map { Array(ids[$0..<min($0 + 2, ids.count)]) }
            VStack(spacing: Self.gap) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { row, pair in
                    HStack(spacing: Self.gap) {
                        ForEach(Array(pair.enumerated()), id: \.element) { column, id in
                            tile(id, index: 1 + row * 2 + column)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ id: String, index: Int, lead: Bool = false) -> some View {
        BentoTile(id: id, module: state.modules.first { $0.id == id }, lead: lead, namespace: namespace)
            .riseIn(index, duration: 0.5, stagger: 0.055)
    }
}

/// A tile: its colour glows in the corner, it lifts under the pointer, and grows into its
/// sheet when clicked.
struct BentoTile: View {
    let id: String
    let module: ModuleSnapshot?
    var lead = false
    let namespace: Namespace.ID
    @Environment(\.islandAccent) private var accent
    @State private var hover = false

    private var color: Color { module?.color ?? accent }

    var body: some View {
        Button { open() } label: {
            Group {
                if lead { LeadTileContent(id: id, module: module) } else { SmallTileContent(id: id, module: module) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                BentoSurface(color: color, lifted: hover, accent: accent)
                    .matchedGeometryEffect(id: "sheet-\(id)", in: namespace)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TilePress())
        .scaleEffect(hover ? 1.012 : 1)
        .offset(y: hover ? -1.5 : 0)
        .animation(.islandSpring(0.35), value: hover)
        .onHover { hover = $0 }
        .accessibilityLabel(loc("Ouvrir \(module?.name ?? loc("À faire"))"))
    }

    private func open() {
        withAnimation(.islandSpring(0.6)) { IslandActions.showModule(id) }
    }
}

/// Pressed, a tile sinks a little.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.islandSpring(0.25), value: configuration.isPressed)
    }
}

/// The ground of a tile and of the sheet it grows into: dark, the module's colour glowing
/// from the top right corner, the island colour round it when the pointer is on it.
struct BentoSurface: View {
    let color: Color
    var lifted = false
    var accent: Color = .clear

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: "#1B1B20"), Color(hex: "#141417")], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.fill(RadialGradient(colors: [color.opacity(0.22), .clear], center: .topTrailing,
                                               startRadius: 0, endRadius: 170)))
            .overlay(shape.strokeBorder(lifted ? accent.opacity(0.6) : Color.white.opacity(0.075), lineWidth: 1))
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 12, y: 6)
    }
}

// MARK: - What a tile shows

/// `.eyebrow`: the module's dot and its name, in small capitals.
struct BentoEyebrow: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text.uppercased())
                .font(IslandTheme.text(9.5, .bold))
                .tracking(0.8)
                .foregroundStyle(IslandTheme.muted)
                .lineLimit(1)
        }
    }
}

/// The large tile: Yumi, and the lead module as he would tell it.
private struct LeadTileContent: View {
    let id: String
    let module: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BentoEyebrow(color: module?.color ?? IslandTheme.violet,
                         text: [module?.name ?? loc("À faire"), module?.status ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            HStack(alignment: .center, spacing: 12) {
                YumiSlot(width: 66)
                if let module, module.id == IslandModel.agentModuleID, let first = module.rows.first {
                    SessionSteps(row: first)
                } else if let module {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(module.title)
                            .font(IslandTheme.round(19, .bold))
                            .foregroundStyle(IslandTheme.fg)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(module.subtitle)
                            .font(IslandTheme.text(11.5))
                            .foregroundStyle(IslandTheme.muted)
                            .lineLimit(1)
                        if let progress = module.progress {
                            ProgressLine(fraction: progress.fraction, color: module.color).padding(.top, 4)
                        }
                    }
                } else {
                    TasksSummary()
                }
            }
            Spacer(minLength: 0)
            if let module, module.id == IslandModel.agentModuleID, module.rows.count > 1 {
                HStack(spacing: 5) {
                    ForEach(module.rows.dropFirst().prefix(3)) { row in
                        SessionPill(row: row) {}
                            .allowsHitTesting(false)
                    }
                }
            } else if let module, !module.primaryAction.isEmpty {
                // The module's own button works from the tile: no need to open the sheet for it
                Button { IslandActions.module(module.id, "primary") } label: {
                    Text(module.primaryAction)
                        .font(IslandTheme.text(11.5, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(module.color.opacity(0.35)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A small tile: the key figure big, one line under it.
private struct SmallTileContent: View {
    let id: String
    let module: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            BentoEyebrow(color: module?.color ?? IslandTheme.violet, text: module?.name ?? loc("À faire"))
            if let module {
                if !module.status.isEmpty {
                    Text(module.status)
                        .font(IslandTheme.round(22, .bold))
                        .monospacedDigit()
                        .foregroundStyle(module.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(module.title)
                    .font(IslandTheme.text(11.5, .medium))
                    .foregroundStyle(IslandTheme.fg.opacity(0.85))
                    .lineLimit(module.status.isEmpty ? 2 : 1)
                if let progress = module.progress {
                    Spacer(minLength: 0)
                    ProgressLine(fraction: progress.fraction, color: module.color)
                }
            } else {
                TasksSummary()
            }
        }
    }
}

/// The tasks tile: what it is for, and the shortcut that fills it.
private struct TasksSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc("Une idée, une tâche"))
                .font(IslandTheme.text(12.5, .semibold))
                .foregroundStyle(IslandTheme.fg)
            Text("⌥ Espace")
                .font(IslandTheme.mono(10.5))
                .foregroundStyle(IslandTheme.muted)
        }
    }
}

struct ProgressLine: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// The large tile when the tab has nothing: Yumi on his own.
private struct YumiTile: View {
    var body: some View {
        IslandCard {
            HStack(spacing: 12) {
                YumiSlot(width: 66)
                VStack(alignment: .leading, spacing: 3) {
                    ActTitle(text: loc("Je ne surveille rien pour l'instant."))
                    ActSub(text: loc("Choisis mes modules dans les réglages de l'app."))
                }
            }
        }
    }
}

// MARK: - The sheet a tile grows into

/// Back to the bento, and the module's name: on top of every sheet.
struct SheetHeader: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.islandSpring(0.5)) { IslandActions.go(.overview) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color(hex: "#26262B")))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(loc("Retour"))
            .accessibilityLabel(loc("Retour"))
            BentoEyebrow(color: color, text: name)
            Spacer(minLength: 0)
        }
    }
}
