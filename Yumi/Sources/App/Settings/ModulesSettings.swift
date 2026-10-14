import SwiftUI

/// Modules: which ones Yumi shows and in what order, then the settings of GitHub, Notion and Agenda.
/// Keys go to the Keychain, under the same names as before.
struct ModulesSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var githubToken = ""
    @State private var githubConnected = KeychainStore.shared.get(IslandActions.githubTokenKey)?.isEmpty == false
    @ObservedObject private var githubApp = GitHubAuth.shared

    var body: some View {
        ScrollViewReader { scroller in
        Form {
            ModuleOrderSections { id in
                withAnimation { scroller.scrollTo("module-settings-\(id)", anchor: .top) }
            }

            Section {
                if GitHubApp.isAvailable { GitHubAppRows() }
                // Signed in with the app, the personal token is not used: no need to show it.
                if !(GitHubApp.isAvailable && githubApp.signedIn) {
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
                }
            } header: {
                Text("GitHub")
            } footer: {
                if GitHubApp.isAvailable {
                    SettingsHelp(loc("L'app GitHub suit chaque compte où tu l'installes, toi et autant d'organisations que tu veux, en lecture seule. Sinon, un jeton en lecture suffit. Je n'écris rien."))
                } else {
                    SettingsHelp(loc("Un jeton en lecture suffit : je regarde tes dépôts, tes pull requests et leurs checks, je n'écris rien."))
                }
            }
            .id("module-settings-github")

            ContributionsSection()
            if githubConnected || (GitHubApp.isAvailable && githubApp.signedIn) { GitHubReposSection() }

            MailSourceSection()
                .id("module-settings-gmail")
            NotionSettingsSection()
                .id("module-settings-notion")

            AgendaSettingsSection()
                .id("module-settings-agenda")
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
    static let withSettings: Set<String> = ["github", "notion", "agenda"]

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

/// GitHub, Contributions: the grid as on the profile, larger, with the total and the streak,
/// whether it shows in the island, and its colours.
private struct ContributionsSection: View {
    @ObservedObject private var contributions = GitHubContributions.shared
    @AppStorage(GitHubContributions.inIslandKey) private var inIsland = true
    @AppStorage(GitHubContributions.paletteKey) private var palette = "yumi"
    @State private var selected: ContributionDay?

    var body: some View {
        Section {
            if let calendar = contributions.calendar {
                ScrollView(.horizontal, showsIndicators: false) {
                    ContributionGrid(calendar: calendar, cell: 9, gap: 2.5, selected: $selected)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(palette == "github" ? 0.9 : 0.85)))
                }
                LabeledContent(loc("Sur un an"), value: calendar.total.formatted(.number.locale(AppLanguage.locale)))
                LabeledContent(loc("Série en cours")) {
                    let streak = calendar.streak(today: GitHubContributionsFeed.day(.now))
                    Text(streak == 1 ? loc("un jour") : loc("\(streak) jours"))
                }
                if let selected { SettingsHelp(ContributionGrid.sentence(for: selected)) }
            } else if let problem = contributions.problem {
                SettingsStatus(text: GitHubContributions.explanation(problem), tone: problem == .noToken ? .off : .warning)
            } else {
                SettingsHelp(loc("Je les lis au prochain passage chez GitHub."))
            }
            Toggle(loc("Afficher dans l'île"), isOn: $inIsland)
            Picker(loc("Couleurs"), selection: $palette) {
                Text("Yumi").tag("yumi")
                Text("GitHub").tag("github")
            }
        } header: {
            Text("Contributions")
        } footer: {
            SettingsHelp(loc("Comme sur ton profil GitHub. Je les relis au plus toutes les trente minutes."))
        }
    }
}

/// The mails module: where the mails come from (Apple's Mail by default, or Gmail), the access
/// to Mail, and which of Mail's accounts the island shows. Gmail's own section follows when chosen.
struct MailSourceSection: View {
    @AppStorage(MailSource.defaultsKey) private var stored = ""
    @State private var hidden = MailAccounts.hidden()
    @ObservedObject private var inbox = GmailInbox.shared
    @State private var access: String?

    private var source: MailSource {
        MailSource(rawValue: stored) ?? MailSource.current(gmailConnected: KeychainStore.shared.get(GmailModule.passwordKey)?.isEmpty == false)
    }

    var body: some View {
        Section {
            if MailSource.mailAppAvailable {
                Picker("Source", selection: Binding(get: { source }, set: { stored = $0.rawValue; changed() })) {
                    Text("App Mail du Mac").tag(MailSource.mailApp)
                    Text("Gmail (mot de passe d'application)").tag(MailSource.gmail)
                }
            }
            if source == .mailApp {
                LabeledContent("Accès à Mail") {
                    HStack {
                        if let access { Text(access).foregroundStyle(.secondary).font(.callout) }
                        Button("Autoriser", action: askAccess)
                    }
                }
                if inbox.accounts.count > 1 {
                    ForEach(inbox.accounts, id: \.self) { account in
                        Toggle(account, isOn: Binding(get: { !hidden.contains(account) }, set: { show(account, $0) }))
                    }
                }
            }
        } header: {
            Text("Mails")
        } footer: {
            SettingsHelp(source == .mailApp
                ? loc("Je lis la boîte de réception de l'app Mail, tous tes comptes, sans aucun mot de passe et sans rien marquer comme lu. Une réponse s'ouvre en brouillon dans Mail : c'est toi qui l'envoies. Si tu refuses l'accès, le module reste vide ; tu peux changer d'avis dans Réglages Système, Confidentialité, Automatisation.")
                : loc("Gmail se lit avec un mot de passe d'application, ci-dessous."))
        }
        if source == .gmail { GmailSettingsSection() }
    }

    private func show(_ account: String, _ on: Bool) {
        var set = hidden
        if on { set.remove(account) } else { set.insert(account) }
        UserDefaults.standard.set(Array(set).sorted(), forKey: MailAccounts.hiddenKey)
        hidden = set
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .gmailSettingsChanged, object: nil)
    }

    /// The click asks macOS for the Automation access to Mail (the system prompt appears once).
    private func askAccess() {
        access = loc("Je demande…")
        Task {
            do {
                _ = try await MailAppScript.run("tell application \"Mail\" to count of accounts", startingMail: true)
                access = loc("Autorisé")
                changed()
            } catch MailAppScript.Failure.denied {
                access = loc("Refusé : Réglages Système, Automatisation")
            } catch {
                access = loc("Mail ne répond pas")
            }
        }
    }
}

/// Gmail: an address and an app password (Google account, Security, App passwords). The
/// password goes to the Keychain, the address to the defaults. Reading is all the module does;
/// an answer leaves only when the person clicks "Envoyer" in the island.
struct GmailSettingsSection: View {
    @State private var address = UserDefaults.standard.string(forKey: GmailModule.addressKey) ?? ""
    @State private var password = ""
    @State private var connected = KeychainStore.shared.get(GmailModule.passwordKey)?.isEmpty == false
    @State private var problem: String?

    var body: some View {
        Section {
            if let problem {
                Text(problem).foregroundStyle(.red).font(.callout)
            }
            LabeledContent("État") {
                SettingsStatus(text: connected ? loc("Branché : \(address)") : loc("Pas branché"), tone: connected ? .ok : .off)
            }
            if connected {
                Button("Débrancher Gmail") {
                    KeychainStore.shared.remove(GmailModule.passwordKey)
                    connected = false
                    NotificationCenter.default.post(name: .gmailSettingsChanged, object: nil)
                }
            } else {
                LabeledContent("Adresse") {
                    TextField("", text: $address, prompt: Text(verbatim: "toi@gmail.com"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                LabeledContent("Mot de passe d'application") {
                    HStack {
                        SecureField("", text: $password, prompt: Text(verbatim: "abcd efgh ijkl mnop"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            .onSubmit(connect)
                        Button("Brancher", action: connect)
                            .disabled(!address.contains("@") || password.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Link(loc("Créer un mot de passe d'application Google"), destination: URL(string: "https://myaccount.google.com/apppasswords")!)
            }
        } header: {
            Text("Gmail")
        } footer: {
            SettingsHelp(loc("Il faut la validation en deux étapes sur ton compte Google. Je lis ta boîte sans rien marquer comme lu ; une réponse ne part que quand tu cliques sur Envoyer dans l'île."))
        }
    }

    private func connect() {
        let mail = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password.replacingOccurrences(of: " ", with: "")
        guard mail.contains("@"), !secret.isEmpty else { return }
        // An app password is exactly 16 letters: anything else is the account's own password,
        // which Gmail refuses
        guard secret.count == 16, secret.allSatisfy(\.isLetter) else {
            problem = loc("Ce n'est pas un mot de passe d'application : Google en donne un de 16 lettres. Ton mot de passe habituel ne marche pas ici.")
            return
        }
        problem = nil
        UserDefaults.standard.set(mail, forKey: GmailModule.addressKey)
        KeychainStore.shared.set(GmailModule.passwordKey, value: secret)
        password = ""
        address = mail
        connected = true
        NotificationCenter.default.post(name: .gmailSettingsChanged, object: nil)
    }
}
