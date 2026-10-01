import SwiftUI

// Modules are shown by their name, in full, after their colour (the "nom" style of the
// mock-up). The first five sit in the island; the others live in a second square, detached
// under it. They are read from `AppState.modules` (Contracts/ModuleTypes.swift).

/// `.mk.d`: the colour of a module, 8 pt, with its margins (0 3px 0 6px)
struct ModuleDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .padding(.leading, 6)
            .padding(.trailing, 3)
    }
}

// MARK: - The row of five (`.o-dock`)

struct IslandDock: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen

    var body: some View {
        let pinned = model.pinned(state.modules)
        let rest = model.others(state.modules).count

        HStack(spacing: 5) {
            ForEach(pinned) { module in
                ModulePill(module: module,
                           on: screen == .module && model.selectedModule(in: state.modules)?.id == module.id) {
                    IslandActions.showModule(module.id)
                }
            }
            if rest > 0 {
                MorePill(count: rest, on: model.drawerOpen) { IslandActions.toggleDrawer() }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 13)
        .padding(.bottom, 16)

        .overlay(alignment: .top) {
            Rectangle().fill(IslandTheme.line).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
}

/// `.pill`
struct ModulePill: View {
    let module: ModuleSnapshot
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let color = Color(hex: module.colorHex)
        Button(action: action) {
            HStack(spacing: 5) {
                ModuleDot(color: color)
                Text(module.name)
                    .font(IslandTheme.round(10.5, .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(on || hover ? IslandTheme.fg : IslandTheme.muted)
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(hover ? IslandTheme.raise : IslandTheme.surface))
            .overlay(Capsule().strokeBorder(color, lineWidth: on ? 1.5 : 0))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .offset(y: hover ? -1 : 0)
        .animation(.islandEase(0.15), value: hover)
        .onHover { hover = $0 }
        .help(module.name)
    }
}

/// `.pill.more`: "+5", opens the second square
struct MorePill: View {
    let count: Int
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text("+\(count)")
                .font(IslandTheme.round(10.5, .bold))
                .monospacedDigit()
                .foregroundStyle(on || hover ? IslandTheme.fg : IslandTheme.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(hover ? IslandTheme.raise : IslandTheme.surface))
                .overlay(Capsule().strokeBorder(IslandTheme.fg, lineWidth: on ? 1.5 : 0))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .offset(y: hover ? -1 : 0)
        .animation(.islandEase(0.15), value: hover)
        .onHover { hover = $0 }
        .accessibilityLabel("Autres modules")
    }
}

// MARK: - The second square (`#drawer`)

struct IslandDrawer: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let shown: Bool

    var body: some View {
        let rest = model.others(state.modules)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(rest.enumerated()), id: \.element.id) { index, module in
                DrawerTile(name: module.name, value: module.status, shown: shown, index: index) {
                    ModuleDot(color: Color(hex: module.colorHex))
                } action: {
                    IslandActions.showModule(module.id)
                }
            }
            DrawerTile(name: "Modules", value: "Gérer", shown: shown, index: rest.count) {
                // `.mk`: a 19 pt black disc with a plus
                IslandGlyphView(glyph: .add, size: 12)
                    .foregroundStyle(IslandTheme.muted)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(.black))
            } action: {
                IslandActions.manageModules()
            }
        }
        .padding(8)
        .frame(width: IslandConst.drawerWidth)
        .background(RoundedRectangle(cornerRadius: 20).fill(.black))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.drawerHeight = $0 }
        // `transform-origin: 78% 0; transform: scale(.6) translateY(-14px); opacity: 0`
        .offset(y: shown ? 0 : -14)
        .scaleEffect(shown ? 1 : 0.6, anchor: UnitPoint(x: 0.78, y: 0))
        .animation(.islandSpring(0.38), value: shown)
        .opacity(shown ? 1 : 0)
        .animation(.islandEase(0.18), value: shown)
        .allowsHitTesting(shown)
    }
}

/// `.tile`
struct DrawerTile<Mark: View>: View {
    let name: String
    let value: String
    let shown: Bool
    let index: Int
    @ViewBuilder let mark: () -> Mark
    let action: () -> Void

    @State private var hover = false
    @State private var risen = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    mark()
                    Text(name)
                        .font(IslandTheme.round(10, .bold))
                        .foregroundStyle(IslandTheme.muted)
                        .lineLimit(1)
                }
                Text(value)
                    .font(IslandTheme.round(13, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(hover ? IslandTheme.raise : IslandTheme.surface))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .offset(y: hover ? -2 : 0)
        .animation(.islandEase(0.15), value: hover)
        .onHover { hover = $0 }
        // `#drawer.on .tile { animation: rise .4s var(--spring) both; animation-delay: calc(var(--i) * 35ms) }`
        .opacity(risen ? 1 : 0)
        .scaleEffect(risen ? 1 : 0.98)
        .offset(y: risen ? 0 : 8)
        .blur(radius: risen ? 0 : 5)
        .onChange(of: shown) { _, on in
            if on {
                withAnimation(.islandSpring(0.4).delay(Double(index) * 0.035)) { risen = true }
            } else {
                risen = false
            }
        }
    }
}
