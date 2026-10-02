import SwiftUI

// The "Mémoire" view, reached from the settings of the island: everything Yumi knows
// (Contracts/MemoryTypes.swift), grouped by nature, the most recent first. A line can be
// corrected or erased, and everything can be erased after a confirmation in the island.
// The core owns the memory: the island only asks, through notifications.

struct MemoryActivity: View {
    @ObservedObject var state: AppState
    @State private var listHeight: CGFloat = 0
    @State private var editing: String?
    @State private var draft = ""
    @State private var confirming = false
    @FocusState private var focused: Bool

    private let listLimit: CGFloat = 176

    /// The groups, in the order of design/yumi/voix.md, each with its most recent line first.
    static func sections(_ entries: [MemoryEntry]) -> [(kind: MemoryEntry.Kind, title: String, entries: [MemoryEntry])] {
        let titles: [(MemoryEntry.Kind, String)] = [(.person, "Toi"), (.project, "Tes projets"), (.thread, "Le fil")]
        return titles.compactMap { kind, title in
            let lines = entries.filter { $0.kind == kind }.sorted { $0.date > $1.date }
            return lines.isEmpty ? nil : (kind, title, lines)
        }
    }

    private var name: String? { FirstName.clean(state.userName ?? "") }
    private var knowsNothing: Bool { state.memory.isEmpty && name == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.riseIn(0)

            if knowsNothing {
                VStack(alignment: .leading, spacing: 3) {
                    ActTitle(text: "Je ne sais encore rien de toi.")
                    ActSub(text: "Ça viendra en parlant. Je retiens ce qui compte, rien d'autre.")
                }
                .riseIn(1)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let name {
                            group("Ton prénom") {
                                Text(name)
                                    .font(IslandTheme.text(12.5, .medium))
                                    .foregroundStyle(IslandTheme.fg)
                                    .padding(.horizontal, 7)
                                    .frame(height: 22)
                            }
                        }
                        ForEach(Self.sections(state.memory), id: \.kind) { section in
                            group(section.title) {
                                ForEach(section.entries) { entry in
                                    if editing == entry.id {
                                        editor(entry)
                                    } else {
                                        MemoryRow(entry: entry) {
                                            draft = entry.text
                                            editing = entry.id
                                            focused = true
                                        } erase: {
                                            IslandActions.forget(entry.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(max(listHeight, 1), listLimit))
                .riseIn(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Back to the settings, the title, and "forget everything" with its confirmation.
    private var header: some View {
        HStack(spacing: 8) {
            Button { IslandActions.go(.settings) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(IslandTheme.muted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages")

            if confirming {
                Text("J'oublie tout, ton prénom aussi ?")
                    .font(IslandTheme.text(12.5, .semibold))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                TextButton(label: "Non, garde") { confirming = false }
                TextButton(label: "Oui, oublie") {
                    confirming = false
                    editing = nil
                    IslandActions.forgetEverything()
                }
            } else {
                Text("Ce que je sais de toi")
                    .font(IslandTheme.text(12.5, .semibold))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !knowsNothing {
                    TextButton(label: "Tout oublier") { confirming = true }
                }
            }
        }
    }

    private func group<Lines: View>(_ title: String, @ViewBuilder lines: () -> Lines) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(IslandTheme.text(10.5, .semibold))
                .foregroundStyle(IslandTheme.faint)
                .padding(.leading, 7)
            lines()
        }
    }

    /// One line being corrected: Return keeps it, Escape or an empty line leaves it as it was.
    private func editor(_ entry: MemoryEntry) -> some View {
        HStack(spacing: 6) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(IslandTheme.text(12.5, .regular))
                .foregroundStyle(IslandTheme.fg)
                .focused($focused)
                .onSubmit { keep(entry) }
                .onExitCommand { editing = nil }
            RoundButton(style: .white, symbol: "checkmark", label: "Garder", small: true) { keep(entry) }
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 17).fill(Color.white.opacity(0.1)))
    }

    private func keep(_ entry: MemoryEntry) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text != entry.text { IslandActions.correct(entry.id, text) }
        editing = nil
    }
}

/// One thing he remembers. The pencil and the cross show while the pointer is on the line.
private struct MemoryRow: View {
    let entry: MemoryEntry
    let edit: () -> Void
    let erase: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 4) {
            Text(entry.text)
                .font(IslandTheme.text(12.5, .regular))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hover {
                icon("pencil", "Corriger", action: edit)
                icon("xmark", "Effacer", action: erase)
            }
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 22)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private func icon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(IslandTheme.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
