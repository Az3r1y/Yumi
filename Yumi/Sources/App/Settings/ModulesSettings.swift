import SwiftUI

/// Modules: GitHub and the pills shown in the island.
/// Keys go to the Keychain, under the same names as before.
struct ModulesSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var githubToken = ""
    @State private var githubConnected = IslandActions.githubConnected

    var body: some View {
        Form {
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
