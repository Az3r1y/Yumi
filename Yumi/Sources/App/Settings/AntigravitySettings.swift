import SwiftUI

/// Antigravity's sessions in the notch: Yumi's entry in ~/.gemini/antigravity-cli/hooks.json,
/// written only after the person has read the change, with a copy of the old file.
struct AntigravityHooksSection: View {
    @State private var installed = AntigravityHooks.isInstalled
    @State private var prepared: Data?
    @State private var preview: String?
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("Sessions") {
                SettingsStatus(text: installed ? loc("Branchés") : loc("Pas branchés"), tone: installed ? .ok : .off)
            }
            HStack {
                Button(installed ? loc("Rebrancher") : loc("Brancher"), action: prepare)
                    .buttonStyle(.borderedProminent)
                Button("Débrancher", action: remove)
                    .disabled(!installed)
                Spacer()
            }
            if let message { SettingsHelp(message) }
            if let preview {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                HStack {
                    Spacer()
                    Button("Annuler") { self.preview = nil; prepared = nil; message = nil }
                    Button("Écrire", action: confirm)
                        .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("Antigravity")
        } footer: {
            SettingsHelp(loc("Mes hooks dans Antigravity me montrent tes sessions agy dans l'encoche. Ils ne décident de rien. Seule l'entrée « yumi » change dans ~/.gemini/antigravity-cli/hooks.json, avec une copie de l'ancien fichier."))
        }
    }

    private var current: Data? { try? Data(contentsOf: AntigravityHooks.fileURL) }

    private func prepare() {
        do {
            let data = try AntigravityHooks.install(current)
            prepared = data
            preview = loc("hooks.json après :") + "\n" + String(decoding: data, as: UTF8.self)
            message = loc("Relis le changement avant de l'écrire.")
        } catch {
            message = loc("hooks.json d'Antigravity n'est pas un JSON valide. Je n'y ai pas touché.")
        }
    }

    private func confirm() {
        guard let prepared else { return }
        do {
            try AntigravityHooks.write(prepared)
            preview = nil
            self.prepared = nil
            installed = AntigravityHooks.isInstalled
            message = loc("C'est branché. Tes prochaines sessions agy apparaîtront dans le module Antigravity.")
        } catch {
            message = loc("L'écriture a échoué : \(error.localizedDescription)")
        }
    }

    private func remove() {
        do {
            try AntigravityHooks.write(AntigravityHooks.remove(current))
            installed = AntigravityHooks.isInstalled
            message = loc("Débranché.")
        } catch {
            message = loc("Je n'ai pas pu débrancher : \(error.localizedDescription)")
        }
    }
}
