import SwiftUI

/// Modules: which ones Yumi shows and in what order, GitHub, and the pills shown in the island.
/// Keys go to the Keychain, under the same names as before.
struct ModulesSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var githubToken = ""
    @State private var githubConnected = IslandActions.githubConnected

    var body: some View {
        Form {
            ModuleOrderSections()

            Section {
                LabeledContent("État") {
                    SettingsStatus(text: githubConnected ? loc("Branché") : loc("Pas de jeton"), tone: githubConnected ? .ok : .off)
                }
                if githubConnected {
                    Button("Retirer le jeton") {
                        IslandActions.connectGitHub(nil)
                        githubConnected = false
                    }
                } else {
                    LabeledContent("Jeton d'accès") {
                        HStack {
                            SecureField("", text: $githubToken, prompt: Text("ghp_…"))
                                .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                                .onSubmit(connectGitHub)
                            Button("Brancher", action: connectGitHub)
                                .disabled(GitHubFigures.cleanToken(githubToken) == nil)
                        }
                    }
                }
            } header: {
                Text("GitHub")
            } footer: {
                SettingsHelp(loc("Un jeton en lecture suffit : je regarde tes dépôts, tes pull requests et leurs checks, je n'écris rien."))
            }
        }
    }

    private func connectGitHub() {
        guard let token = GitHubFigures.cleanToken(githubToken) else { return }
        IslandActions.connectGitHub(token)
        githubToken = ""
        githubConnected = true
    }
}

/// The modules, in the order of the island: the first ones in the island, the next ones in the
/// second square, the hidden ones last. Dragged with the mouse, moved with the arrows of each row (reachable with Tab), shown or
/// hidden with their switch. The same list as the island's edit mode (ModuleLineup).
private struct ModuleOrderSections: View {
    @ObservedObject private var lineup = ModuleLineup.shared

    var body: some View {
        let shown = lineup.selected
        Section {
            if shown.isEmpty {
                SettingsHelp(loc("Aucun module affiché. Active-en un ci-dessous."))
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                row(entry, index: index, count: shown.count)
            }
            .onMove { from, to in
                guard let first = from.first else { return }
                let id = shown[first].id
                lineup.move(id, to: to > first ? to - 1 : to)
            }
        } header: {
            Text("Modules affichés")
        } footer: {
            SettingsHelp(loc("Les \(ModuleCatalog.pinnedLimit) premiers vont dans l'île, les suivants dans le second carré. Glisse-les pour changer l'ordre, ou utilise les flèches de chaque ligne (Tab pour y aller au clavier)."))
        }

        if !lineup.hidden.isEmpty {
            Section("Modules masqués") {
                ForEach(lineup.hidden) { entry in
                    HStack(spacing: 10) {
                        ModuleIcon(entry: entry)
                        Text(entry.snapshot.name).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(get: { false }, set: { if $0 { lineup.setShown(entry.id, true) } }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(loc("Afficher \(entry.snapshot.name)"))
                    }
                }
            }
        }
    }

    private func row(_ entry: ModuleLineup.Entry, index: Int, count: Int) -> some View {
        let place = ModuleLineup.place(of: index, selected: true)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            ModuleIcon(entry: entry)
            Text(entry.snapshot.name)
            Spacer()
            Text(place == .island ? loc("Dans l'île") : loc("Second carré"))
                .font(.caption)
                .foregroundStyle(place == .island ? Color.accentColor : .secondary)
            Button { lineup.nudge(entry.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help(loc("Monter"))
            Button { lineup.nudge(entry.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(index == count - 1)
                .help(loc("Descendre"))
            Toggle("", isOn: Binding(get: { true }, set: { if !$0 { lineup.setShown(entry.id, false) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(loc("Masquer \(entry.snapshot.name)"))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: loc("Monter")) { lineup.nudge(entry.id, by: -1) }
        .accessibilityAction(named: loc("Descendre")) { lineup.nudge(entry.id, by: 1) }
    }
}

/// The module's symbol on a tile of its colour.
struct ModuleIcon: View {
    let entry: ModuleLineup.Entry

    var body: some View {
        Image(systemName: entry.snapshot.glyph)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(entry.snapshot.color))
    }
}
