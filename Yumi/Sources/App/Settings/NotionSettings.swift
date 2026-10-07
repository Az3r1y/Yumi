import SwiftUI

/// Settings, Modules, Notion: the integration key, a test, and the databases to follow with
/// the meaning of their properties. Only the databases chosen here are ever read.
struct NotionSettingsSection: View {
    @State private var key = ""
    @State private var connected = KeychainStore.shared.get("notion-integration-key") != nil
    @State private var databases: [NotionDatabase] = []
    @State private var chosen: [NotionBase] = NotionBases.load()
    @State private var status: String?
    @State private var loading = false

    private var api: NotionAPI { YumiCore.notionAPI }

    var body: some View {
        Section {
            if connected {
                LabeledContent(loc("État")) { SettingsStatus(text: status ?? loc("Clé enregistrée"), tone: status == nil ? .ok : .warning) }
                HStack {
                    Button(loc("Tester")) { Task { await refresh() } }.disabled(loading)
                    Button(loc("Retirer la clé")) {
                        KeychainStore.shared.remove("notion-integration-key")
                        connected = false
                        databases = []
                        changed()
                    }
                }
            } else {
                LabeledContent(loc("Clé d'intégration")) {
                    HStack {
                        SecureField("", text: $key, prompt: Text("ntn_…")).labelsHidden()
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        Button(loc("Brancher")) {
                            KeychainStore.shared.set("notion-integration-key", value: key.trimmingCharacters(in: .whitespacesAndNewlines))
                            key = ""
                            connected = true
                            Task { await refresh() }
                            changed()
                        }
                        .disabled(key.nonEmptyTrimmed == nil)
                    }
                }
            }
            ForEach(databases, id: \.id) { database in base(database) }
        } header: {
            Text("Notion")
        } footer: {
            SettingsHelp(loc("Crée une intégration interne sur notion.so/my-integrations, colle sa clé ici, puis dans chaque base à suivre ouvre « … », « Connexions » et ajoute l'intégration. Je ne lis que les bases cochées ici, et je n'y ajoute une tâche qu'avec ton accord."))
        }
        .task { if connected { await refresh() } }
    }

    @ViewBuilder
    private func base(_ database: NotionDatabase) -> some View {
        let index = chosen.firstIndex { $0.id == database.id }
        Toggle(database.name, isOn: Binding(get: { index != nil }, set: { on in
            if on, let title = database.titleProperty {
                chosen.append(NotionBase(id: database.id, name: database.name, titleProperty: title,
                                         dateProperty: database.names(ofType: "date").first,
                                         doneProperty: database.names(ofType: "checkbox").first ?? database.names(ofType: "status").first,
                                         doneIsCheckbox: !database.names(ofType: "checkbox").isEmpty,
                                         doneValue: database.names(ofType: "checkbox").isEmpty
                                            ? database.names(ofType: "status").first.flatMap { database.statusOptions[$0]?.last } : nil))
            } else {
                chosen.removeAll { $0.id == database.id }
            }
            save()
        }))
        if let index {
            Picker(loc("Date"), selection: Binding(get: { chosen[index].dateProperty ?? "" },
                                                   set: { chosen[index].dateProperty = $0.isEmpty ? nil : $0; save() })) {
                Text(loc("Aucune")).tag("")
                ForEach(database.names(ofType: "date"), id: \.self) { Text($0).tag($0) }
            }
            Picker(loc("Terminé"), selection: Binding(get: { chosen[index].doneProperty ?? "" }, set: { name in
                chosen[index].doneProperty = name.isEmpty ? nil : name
                chosen[index].doneIsCheckbox = database.properties[name] == "checkbox"
                chosen[index].doneValue = chosen[index].doneIsCheckbox ? nil : database.statusOptions[name]?.last
                save()
            })) {
                Text(loc("Aucune")).tag("")
                ForEach(database.names(ofType: "checkbox") + database.names(ofType: "status"), id: \.self) { Text($0).tag($0) }
            }
            if let done = chosen[index].doneProperty, !chosen[index].doneIsCheckbox {
                Picker(loc("Valeur « terminé »"), selection: Binding(get: { chosen[index].doneValue ?? "" },
                                                                    set: { chosen[index].doneValue = $0; save() })) {
                    ForEach(database.statusOptions[done] ?? [], id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            databases = try await api.databases()
            status = databases.isEmpty ? loc("Aucune base partagée avec l'intégration") : nil
        } catch {
            status = FrenchText.sentenceStart(error.reason)
        }
    }

    private func save() {
        NotionBases.save(chosen)
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .notionSettingsChanged, object: nil)
    }
}
