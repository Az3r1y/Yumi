import SwiftUI

/// Modules: which ones Yumi shows and in what order, then the settings of GitHub and Notion.
/// Keys go to the Keychain, under the same names as before.
struct ModulesSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var githubToken = ""
    @State private var githubConnected = IslandActions.githubConnected

    var body: some View {
        ScrollViewReader { scroller in
        Form {
            ModuleOrderSections { id in
                withAnimation { scroller.scrollTo("module-settings-\(id)", anchor: .top) }
            }

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
            .id("module-settings-github")
            if githubConnected { GitHubReposSection() }

            NotionSettingsSection()
                .id("module-settings-notion")
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
    /// Shows the settings of a module further down the page.
    var showSettings: (String) -> Void = { _ in }
    /// The modules that have their own settings on this page.
    static let withSettings: Set<String> = ["github", "notion"]

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
                        if Self.withSettings.contains(entry.id) {
                            Button { showSettings(entry.id) } label: { Image(systemName: "gearshape") }
                                .buttonStyle(.borderless)
                                .help(loc("Réglages de \(entry.snapshot.name)"))
                        }
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
            if Self.withSettings.contains(entry.id) {
                Button { showSettings(entry.id) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help(loc("Réglages de \(entry.snapshot.name)"))
            }
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

/// The repositories GitHub showed, all followed by default: untick one to hide it everywhere
/// (activity, pull requests, scenes). And what the token needs.
struct GitHubReposSection: View {
    @State private var hidden = GitHubRepos.hidden()
    private let known = GitHubRepos.known()
    private let login = UserDefaults.standard.string(forKey: GitHubRepos.loginKey)

    var body: some View {
        Section {
            LabeledContent(loc("Compte")) { Text(login ?? loc("pas encore lu")).foregroundStyle(.secondary) }
            if known.isEmpty {
                SettingsHelp(loc("La liste arrive après la première lecture de GitHub."))
            }
            ForEach(known, id: \.self) { repo in
                Toggle(repo, isOn: Binding(get: { !hidden.contains(repo) }, set: { shown in
                    if shown { hidden.remove(repo) } else { hidden.insert(repo) }
                    GitHubRepos.setHidden(hidden)
                    NotificationCenter.default.post(name: .githubReposChanged, object: nil)
                }))
            }
        } header: {
            Text(loc("Dépôts suivis"))
        } footer: {
            SettingsHelp(loc("Tous tes dépôts sont suivis : les tiens, ceux où tu collabores et ceux de tes organisations que le jeton voit. Un jeton classique avec « repo » (et « read:org » pour les organisations), ou un jeton à granularité fine en lecture seule sur Contents, Metadata, Pull requests et Checks, suffit. Je ne fais que lire, et seulement auprès de api.github.com."))
        }
    }
}
