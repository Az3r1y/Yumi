import AppKit
import SwiftUI

/// Signing in with the Yumi GitHub App (Modules/GitHub/GitHubApp.swift): the device flow, the
/// token in the Keychain, and its renewal before it expires. The personal token stays the other
/// way in; when both are there, the app's token wins.
@MainActor
final class GitHubAuth: ObservableObject {
    static let shared = GitHubAuth()

    enum Step: Equatable {
        case idle
        /// The code to type on github.com.
        case waiting(GitHubApp.DeviceCode)
        case failed(String)
    }

    @Published private(set) var step: Step = .idle
    @Published private(set) var signedIn = GitHubAuth.stored != nil

    private var flow: Task<Void, Never>?
    private var renewal: Task<Void, Never>?

    private static var stored: GitHubApp.Token? { GitHubApp.Token.decode(KeychainStore.shared.get(GitHubApp.tokenKey)) }

    /// True when the module should list the app's installations.
    static var viaApp: Bool { GitHubApp.isAvailable && stored != nil }

    /// The token the GitHub module sends: the app's, else the personal one.
    static var currentToken: String? {
        if GitHubApp.isAvailable, let token = stored?.usable(now: .now) { return token }
        return KeychainStore.shared.get(IslandActions.githubTokenKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Device flow

    func start() {
        guard GitHubApp.isAvailable, LaunchPlan.current.keychain else { return }
        flow?.cancel()
        step = .idle
        flow = Task { [weak self] in await self?.run() }
    }

    func cancel() {
        flow?.cancel()
        flow = nil
        step = .idle
    }

    func signOut() {
        cancel()
        KeychainStore.shared.remove(GitHubApp.tokenKey)
        signedIn = false
        IslandActions.tap()
        Self.tellModule()
    }

    private func run() async {
        let clientID = GitHubApp.clientID
        guard let answer = try? await URLSession.shared.data(for: GitHubApp.deviceCodeRequest(clientID: clientID)),
              let code = GitHubApp.deviceCode(from: answer.0, now: .now) else {
            step = .failed(loc("GitHub ne répond pas. Réessaie dans un moment."))
            return
        }
        step = .waiting(code)
        NSWorkspace.shared.open(code.verificationURL)
        var interval = code.interval
        while !Task.isCancelled, Date.now < code.expires {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            guard let answer = try? await URLSession.shared.data(for: GitHubApp.pollRequest(clientID: clientID, deviceCode: code.deviceCode)) else { continue }
            switch GitHubApp.poll(from: answer.0, now: .now) {
            case .token(let token):
                save(token)
                step = .idle
                SoundEngine.shared.play("approve")
                return
            case .pending:
                continue
            case .slowDown(let longer):
                interval = longer
            case .expired:
                step = .failed(loc("Le code a expiré. Recommence."))
                return
            case .denied:
                step = .failed(loc("Connexion annulée sur GitHub."))
                return
            case .failed(let error):
                step = .failed(loc("GitHub a refusé la connexion (\(error))."))
                return
            }
        }
        if !Task.isCancelled { step = .failed(loc("Le code a expiré. Recommence.")) }
    }

    private func save(_ token: GitHubApp.Token) {
        guard let text = token.encoded else { return }
        KeychainStore.shared.set(GitHubApp.tokenKey, value: text)
        signedIn = true
        Self.tellModule()
    }

    // MARK: Renewal

    /// Called by the module before each look: renews the token in its last minutes. Without a
    /// secret, since it came from the device flow. A refused refresh token signs out.
    func renewIfNeeded() async {
        if let renewal { return await renewal.value }
        guard GitHubApp.isAvailable, let token = Self.stored, token.needsRefresh(now: .now) else { return }
        guard token.canRefresh(now: .now), let refresh = token.refresh else {
            if token.usable(now: .now) == nil { forget() }
            return
        }
        let task = Task { [weak self] in
            guard let answer = try? await URLSession.shared.data(for: GitHubApp.refreshRequest(clientID: GitHubApp.clientID, refreshToken: refresh)) else { return }
            guard let self else { return }
            switch GitHubApp.poll(from: answer.0, now: .now) {
            case .token(let fresh):
                guard let text = fresh.encoded else { return }
                KeychainStore.shared.set(GitHubApp.tokenKey, value: text)
            case .failed("bad_refresh_token"):
                self.forget()
            default:
                break
            }
        }
        renewal = task
        await task.value
        renewal = nil
    }

    /// The token no longer works: sign in again.
    private func forget() {
        KeychainStore.shared.remove(GitHubApp.tokenKey)
        signedIn = false
    }

    private static func tellModule() {
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": "github", "action": "secondary"])
    }
}

/// Settings, Modules, GitHub: the app's way in, shown only once the app is registered.
struct GitHubAppRows: View {
    @ObservedObject private var auth = GitHubAuth.shared

    var body: some View {
        if auth.signedIn {
            LabeledContent(loc("App GitHub")) { SettingsStatus(text: loc("Connectée"), tone: .ok) }
            HStack {
                if let install = GitHubApp.installURL {
                    Link(loc("Ajouter une organisation"), destination: install)
                }
                Spacer()
                Button(loc("Déconnecter l'app")) { auth.signOut() }
            }
        } else {
            switch auth.step {
            case .waiting(let code):
                LabeledContent(loc("Code à taper sur GitHub")) {
                    HStack {
                        Text(verbatim: code.userCode)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Button(loc("Copier")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code.userCode, forType: .string)
                        }
                    }
                }
                HStack {
                    Link(loc("Ouvrir GitHub"), destination: code.verificationURL)
                    Spacer()
                    Button(loc("Annuler")) { auth.cancel() }
                }
            case .failed(let problem):
                Text(problem).foregroundStyle(.red).font(.callout)
                Button(loc("Se connecter avec l'app GitHub")) { auth.start() }
            case .idle:
                LabeledContent(loc("App GitHub")) {
                    Button(loc("Se connecter avec l'app GitHub")) { auth.start() }
                }
            }
        }
    }
}
