import SwiftUI

// The rail at the bottom of the open island, always there (`.rail` in the mock-up): the
// overview, one icon per module, then the chat and the settings. The one on screen opens
// into its name; a dot marks what is live; hovering shows the name in a label.

struct IslandRail: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen
    /// The module on screen, if the screen is about one.
    let moduleID: String?

    var body: some View {
        HStack(spacing: 1) {
            RailButton(symbol: "square.grid.2x2.fill", name: "Tous", label: "Tous les modules",
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
            RailButton(symbol: "bubble.left", name: "Parler", label: "Parler à Yumi",
                       color: IslandTheme.violet, on: screen == .talk, bright: true) {
                IslandActions.go(.prompt)
            }
            RailButton(symbol: "gearshape", name: "Réglages", label: "Réglages",
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

struct OverviewActivity: View {
    @ObservedObject var state: AppState

    var body: some View {
        let modules = Array(state.modules.prefix(ModuleCatalog.selectionLimit))
        if modules.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ActTitle(text: "Je ne surveille rien pour l'instant.")
                ActSub(text: "Choisis mes modules dans les réglages de l'app.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // `.ovr { grid-template-columns: 1.3fr 1fr; gap: 1px 8px }`
            GeometryReader { geo in
                let first = (geo.size.width - 8) * 1.3 / 2.3
                let rows = stride(from: 0, to: modules.count, by: 2).map { Array(modules[$0..<min($0 + 2, modules.count)]) }
                VStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 8) {
                            OverviewRow(module: row[0]).frame(width: first)
                            if row.count > 1 { OverviewRow(module: row[1]) } else { Spacer(minLength: 0) }
                        }
                        .riseIn(index, stagger: 0.03)
                    }
                }
            }
            .frame(height: CGFloat((modules.count + 1) / 2) * OverviewRow.height + CGFloat(max(0, (modules.count + 1) / 2 - 1)))
        }
    }
}

/// `.orow`: icon, full name, key figure.
private struct OverviewRow: View {
    static let height: CGFloat = 23
    let module: ModuleSnapshot
    @State private var hover = false

    var body: some View {
        Button(action: { IslandActions.showModule(module.id) }) {
            HStack(spacing: 7) {
                Image(systemName: module.glyph)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(module.color)
                    .frame(width: 15, height: 14)
                Text(module.name)
                    .font(IslandTheme.text(12, .medium))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(module.status)
                    .font(IslandTheme.round(11.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(module.color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
