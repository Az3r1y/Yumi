import SwiftUI

/// Modules: GitHub, the services that need a key, and the pills shown in the island.
/// Keys go to the Keychain, under the same names as before.
struct ModulesSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var githubToken = ""
    @State private var githubConnected = IslandActions.githubConnected

    var body: some View {
        Form {
            Section {
                LabeledContent("État") {
                    SettingsStatus(text: githubConnected ? "Branché" : "Pas de jeton", tone: githubConnected ? .ok : .off)
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
                SettingsHelp("Un jeton en lecture suffit : je regarde tes dépôts, tes pull requests et leurs checks, je n'écris rien.")
            }

            IntegrationSection(name: "Resend", color: "#22C55E", fields: [
                .init(key: "resend-api-key", label: "Clé API", prompt: "re_…", secret: true),
                .init(key: "resend-from", label: "Adresse d'envoi", prompt: "toi@ton-domaine.fr", secret: false),
            ])
            IntegrationSection(name: "n8n", color: "#F29B38", fields: [
                .init(key: "n8n-url", label: "Adresse de l'instance", prompt: "https://…", secret: false),
                .init(key: "n8n-api-key", label: "Clé API", prompt: "", secret: true),
            ]) {
                FilterList(label: "Workflows suivis", filter: $state.n8nWorkflowFilter, load: IntegrationLists.n8nWorkflows)
            }
            IntegrationSection(name: "Vercel", color: "#7C5CFF", fields: [
                .init(key: "vercel-token", label: "Jeton", prompt: "", secret: true),
            ]) {
                FilterList(label: "Projets suivis", filter: $state.vercelProjectFilter, load: IntegrationLists.vercelProjects)
            }
            IntegrationSection(name: "Stripe", color: "#0570DE", fields: [
                .init(key: "stripe-api-key", label: "Clé secrète", prompt: "sk_live_… ou sk_test_…", secret: true),
            ])
            IntegrationSection(name: "Cal.com", color: "#C9956A", fields: [
                .init(key: "calcom-api-key", label: "Clé API", prompt: "cal_live_…", secret: true),
            ])
            IntegrationSection(name: "Notion", color: "#E8E8E8", fields: [
                .init(key: "notion-api-key", label: "Jeton d'intégration", prompt: "secret_…", secret: true),
            ])

            Section {
                LabeledContent("VS Code") { Text("Toujours affiché").foregroundStyle(.secondary) }
                ForEach(AgentTask.toggleableIntegrationIds, id: \.self) { id in
                    if let task = AgentTask.integrationAgents.first(where: { $0.id == id }) {
                        let on = state.activeIntegrations.contains(id)
                        Toggle(isOn: Binding(get: { on }, set: { _ in state.toggleIntegration(id) })) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                                Text(task.name)
                            }
                        }
                        .disabled(!on && state.activeIntegrations.count >= 4)
                    }
                }
            } header: {
                Text("Pastilles de l'île")
            } footer: {
                SettingsHelp("\(state.activeIntegrations.count) sur 4. Pour en montrer une autre, retires-en une.")
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

/// One service with a key: its fields, whether it is saved, one button to save it.
private struct IntegrationSection<Extra: View>: View {
    struct Field: Identifiable {
        let key: String
        let label: String
        let prompt: String
        let secret: Bool
        var id: String { key }
    }

    let name: String
    let color: String
    let fields: [Field]
    let extra: Extra
    @State private var values: [String: String] = [:]
    @State private var saved = false

    init(name: String, color: String, fields: [Field], @ViewBuilder extra: () -> Extra) {
        self.name = name
        self.color = color
        self.fields = fields
        self.extra = extra()
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: fields.map { ($0.key, KeychainStore.shared.get($0.key) ?? "") }))
    }

    private var stored: Bool { fields.contains { KeychainStore.shared.get($0.key)?.isEmpty == false } || saved && !values.values.allSatisfy(\.isEmpty) }

    var body: some View {
        Section {
            ForEach(fields) { field in
                LabeledContent(field.label) {
                    Group {
                        if field.secret {
                            SecureField("", text: binding(field.key), prompt: Text(field.prompt))
                        } else {
                            TextField("", text: binding(field.key), prompt: Text(field.prompt))
                        }
                    }
                    .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
            }
            HStack {
                SettingsStatus(text: stored ? "Enregistré" : "Pas de clé", tone: stored ? .ok : .off)
                Spacer()
                Button("Enregistrer", action: save)
            }
            extra
        } header: {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
                Text(name)
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0; saved = false })
    }

    /// An empty field removes the key.
    private func save() {
        for field in fields {
            let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { KeychainStore.shared.remove(field.key) } else { KeychainStore.shared.set(field.key, value: value) }
        }
        saved = true
    }
}

extension IntegrationSection where Extra == EmptyView {
    init(name: String, color: String, fields: [Field]) {
        self.init(name: name, color: color, fields: fields) { EmptyView() }
    }
}

/// The projects or workflows of a service, to follow only some of them. Empty: all of them.
private struct FilterList: View {
    let label: String
    @Binding var filter: Set<String>
    let load: () async -> [String]?
    @State private var items: [String] = []
    @State private var loading = false
    @State private var problem: String?

    var body: some View {
        IntegrationFilterRow(label: label, items: items, filter: $filter, loading: loading) {
            loading = true
            Task {
                let found = await load()
                items = found ?? []
                problem = found == nil ? "Enregistre d'abord la clé." : found?.isEmpty == true ? "Je n'ai rien trouvé." : nil
                loading = false
            }
        }
        if let problem { SettingsHelp(problem) }
    }
}

/// The lists the old window loaded, with the keys saved in the Keychain. nil without a key.
enum IntegrationLists {
    static func vercelProjects() async -> [String]? {
        guard let token = KeychainStore.shared.get("vercel-token"),
              let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]] else { return [] }
        return projects.compactMap { $0["name"] as? String }.sorted()
    }

    static func n8nWorkflows() async -> [String]? {
        guard let key = KeychainStore.shared.get("n8n-api-key"), let raw = KeychainStore.shared.get("n8n-url") else { return nil }
        let base = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for path in ["\(base)/api/v1/workflows?limit=100", "\(base)/rest/workflows?limit=100"] {
            guard let url = URL(string: path) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(key, forHTTPHeaderField: "X-N8N-API-KEY")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let object = try? JSONSerialization.jsonObject(with: data)
            let items = (object as? [String: Any])?["data"] as? [[String: Any]] ?? object as? [[String: Any]] ?? []
            return items.compactMap { $0["name"] as? String }.sorted()
        }
        return []
    }
}
