import SwiftUI
import AppKit
import EventKit
import CoreLocation

/// Autorisations: what macOS lets the app do, then what Yumi may do without asking.
struct PermissionsSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var states = MacPermission.current()

    var body: some View {
        Form {
            Section {
                ForEach(MacPermission.allCases) { permission in
                    LabeledContent(permission.title) {
                        HStack {
                            let value = states[permission]
                            SettingsStatus(text: MacPermission.label(value), tone: value == .granted ? .ok : value == .denied ? .warning : .off)
                            Button(value == .granted ? loc("Réglages…") : loc("Autoriser…")) {
                                NSWorkspace.shared.open(permission.settingsURL)
                            }
                        }
                    }
                }
            } header: {
                Text("macOS")
            } footer: {
                SettingsHelp(loc("Ces accès se donnent dans les Réglages Système. Je ne les demande que quand un module en a besoin."))
            }

            Section {
                PermissionsPanel(state: state)
            } header: {
                Text("Ce que je fais sans te demander")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            states = MacPermission.current()
        }
    }
}

/// The macOS accesses Yumi's modules use, read without ever asking for them.
enum MacPermission: String, CaseIterable, Identifiable {
    case accessibility, calendars, reminders, location, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return loc("Accessibilité")
        case .calendars:     return "Calendrier"
        case .reminders:     return "Rappels"
        case .location:      return "Position"
        case .automation:    return "Automatisation"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility: return AccessibilityPermission.settingsURL
        case .calendars:     return PrivacySettings.calendars
        case .reminders:     return PrivacySettings.reminders
        case .location:      return PrivacySettings.location
        case .automation:    return PrivacySettings.automation
        }
    }

    /// nil: macOS does not tell (automation, Accessibility in the App Store build).
    @MainActor static func current() -> [MacPermission: PermissionState] {
        var states: [MacPermission: PermissionState] = [:]
        switch AccessibilityPermission.status() {
        case .granted:    states[.accessibility] = .granted
        case .notGranted: states[.accessibility] = .denied
        default:          break
        }
        states[.calendars] = state(EKEventStore.authorizationStatus(for: .event))
        states[.reminders] = state(EKEventStore.authorizationStatus(for: .reminder))
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:             states[.location] = .notDetermined
        case .denied, .restricted:       states[.location] = .denied
        default:                         states[.location] = .granted
        }
        return states
    }

    private static func state(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined:       return .notDetermined
        case .denied, .restricted: return .denied
        default:                   return .granted
        }
    }

    static func label(_ state: PermissionState?) -> String {
        switch state {
        case .granted?:       return loc("Autorisé")
        case .denied?:        return loc("Refusé")
        case .notDetermined?: return loc("Pas demandé")
        case nil:             return "Inconnu"
        }
    }
}

/// Mémoire: what Yumi knows of the person. The list itself is read and edited in the island.
struct MemorySettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                LabeledContent(loc("Ton prénom"), value: state.userName ?? loc("Je ne le connais pas encore"))
                LabeledContent("Souvenirs", value: state.memory.isEmpty ? "Aucun" : "\(state.memory.count)")
                Button("Voir et modifier dans l'île") {
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.memory)
                }
                Button("Tout effacer…", role: .destructive) { confirmClear = true }
                    .disabled(state.memory.isEmpty)
                    .confirmationDialog("Tout effacer de ma mémoire ?", isPresented: $confirmClear) {
                        Button("Tout effacer", role: .destructive) {
                            IslandActions.forgetEverything()
                        }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("J'oublierai tout ce que tu m'as dit. Ça ne se rattrape pas.")
                    }
            } footer: {
                SettingsHelp(loc("Je ne garde que ce que tu m'as dit, sur ce Mac. Tu peux tout relire, corriger ou effacer dans l'île."))
            }
        }
    }
}

/// À propos: the version, new versions, feedback, licences, and the developer tools switch.
struct AboutSettings: View {
    @ObservedObject private var updates = YumiUpdates.shared
    @AppStorage(SettingsPage.developerKey) private var developer = false

    var body: some View {
        Form {
            Section {
                LabeledContent(AppIdentity.productName, value: YumiUpdates.installed)
                Toggle("Me prévenir des nouvelles versions", isOn: Binding(get: { updates.enabled }, set: { updates.enabled = $0 }))
                if let newer = updates.newer {
                    LabeledContent("Nouvelle version") {
                        HStack {
                            SettingsStatus(text: loc("\(newer.tag) est là"), tone: .warning)
                            Button("Voir") { updates.openRelease() }
                        }
                    }
                }
            } footer: {
                SettingsHelp(loc("Je regarde une fois par jour sur GitHub. Je ne télécharge et n'installe jamais rien tout seul."))
            }

            Section {
                LabeledContent("Un bug, une idée") {
                    HStack {
                        Button("Envoyer un retour") {
                            if let url = YumiUpdates.feedbackURL() { NSWorkspace.shared.open(url) }
                        }
                        Button("Sur GitHub") {
                            if let url = YumiUpdates.githubFeedbackURL() { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                LabeledContent("Licences") {
                    Button("Voir") {
                        if let url = URL(string: "https://github.com/estebanbaigts/Yumi/blob/main/LICENSE") { NSWorkspace.shared.open(url) }
                    }
                }
            } footer: {
                SettingsHelp(loc("Le retour s'ouvre sur GitHub avec la version de Yumi, de macOS et le modèle de ton Mac déjà remplis. Rien d'autre."))
            }

            Section {
                Toggle("Afficher les outils de développeur", isOn: $developer)
            }
        }
    }
}

/// Développeur: the panels used to try the context and the agent by hand.
struct DeveloperSettings: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Form {
            Section("Contexte") {
                ContextDebugPanel(state: state)
            }
            Section("Agent") {
                AgentDebugPanel(state: state)
            }
        }
    }
}
