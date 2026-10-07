import SwiftUI
import ServiceManagement

/// Général: when Yumi starts, how the island opens and folds, and what he looks at.
struct GeneralSettings: View {
    @ObservedObject private var state = AppState.shared
    @State private var launchAtStartup = SMAppService.mainApp.status == .enabled
    @State private var startupError: String?
    @State private var hotkeyFlags = AppState.shared.hotkeyFlags
    @State private var hotkeyCode = AppState.shared.hotkeyCode
    @AppStorage(TripleShift.defaultsKey) private var tripleShift = true
    @State private var language = AppLanguage.stored()

    /// The same choices as the island's own settings; 0 is never.
    static let foldDelays: [(seconds: TimeInterval, label: String)] =
        [(5, "5 secondes"), (15, "15 secondes"), (30, "30 secondes"), (60, "1 minute"), (0, "Jamais")]

    var body: some View {
        Form {
            Section {
                Picker("Langue", selection: Binding(get: { language }, set: { language = $0; AppLanguage.choose($0) })) {
                    Text("Automatique").tag(AppLanguage.automatic)
                    Text(verbatim: "Français").tag(AppLanguage.french)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
            } footer: {
                if languageChanges {
                    SettingsHelp(loc("La nouvelle langue s'applique au prochain lancement de Yumi."))
                } else {
                    SettingsHelp(loc("En automatique, je parle la langue de ton Mac."))
                }
            }

            Section {
                Toggle("Ouvrir Yumi au démarrage du Mac", isOn: $launchAtStartup)
                    .onChange(of: launchAtStartup) { _, on in setStartup(on) }
                if let startupError { SettingsHelp(startupError) }
            }

            Section("Île") {
                Picker("Se replier après", selection: Binding(get: { foldDelay }, set: { state.autoCloseInterval = $0 })) {
                    ForEach(Self.foldDelays, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                LabeledContent("Se cacher sans mouvement après") {
                    Stepper(value: absenceMinutes, in: 1...60) {
                        Text("\(Int(absenceMinutes.wrappedValue)) min").monospacedDigit()
                    }
                }
                Toggle("Ouvrir l'île avec trois appuis sur Maj", isOn: $tripleShift)
                Toggle("Ouvrir l'île avec un raccourci", isOn: $state.hotkeyEnabled)
                if state.hotkeyEnabled {
                    LabeledContent("Raccourci") {
                        ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                            .onChange(of: hotkeyFlags) { _, value in state.hotkeyFlags = value }
                            .onChange(of: hotkeyCode) { _, value in state.hotkeyCode = value }
                    }
                }
            }

            Section {
                Toggle("Regarder l'app au premier plan", isOn: $state.contextEnabled)
            } header: {
                Text("Contexte")
            } footer: {
                SettingsHelp(loc("Je vois quelle app et quelle fenêtre tu utilises, pour parler à propos. Ça reste sur ce Mac, en mémoire : pas de capture d'écran, pas de frappe."))
            }
        }
    }

    /// True when the language chosen is not the one this run speaks.
    private var languageChanges: Bool {
        let wanted = language.code ?? AppLanguage.resolve(Locale.preferredLanguages.first)
        return wanted != AppLanguage.current
    }

    /// The stored delay, on the nearest choice when an older value is not one of them.
    private var foldDelay: TimeInterval {
        let value = state.autoCloseInterval
        if value <= 0 { return 0 }
        return Self.foldDelays.filter { $0.seconds > 0 }.min { abs($0.seconds - value) < abs($1.seconds - value) }?.seconds ?? 15
    }

    private var absenceMinutes: Binding<Double> {
        Binding(get: { (state.absenceInterval / 60).rounded() }, set: { state.absenceInterval = max(1, $0) * 60 })
    }

    private func setStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            startupError = nil
        } catch {
            startupError = loc("macOS a refusé : \(error.localizedDescription)")
            launchAtStartup = !on
        }
    }
}

/// Yumi: his sounds, his habit while an agent works, how much he speaks first.
struct YumiSettings: View {
    @ObservedObject private var state = AppState.shared
    @AppStorage(IslandPrefs.workHabitKey) private var workHabit = YumiWorkHabit.current().rawValue
    @AppStorage(YumiTalk.defaultsKey) private var talk = YumiTalk.discreet.rawValue

    var body: some View {
        Form {
            Section("Son") {
                Toggle("Sons", isOn: $state.soundEnabled)
                LabeledContent("Volume") {
                    HStack {
                        Slider(value: $state.soundVolume, in: 0...0.2) { editing in
                            if !editing { SoundEngine.shared.play("pop") }
                        }
                        .frame(maxWidth: 220)
                        Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!state.soundEnabled)
            }

            Section {
                Picker("Pendant qu'un agent bosse", selection: $workHabit) {
                    ForEach(YumiWorkHabit.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Je parle de moi-même", selection: $talk) {
                    Text("Jamais").tag(YumiTalk.silent.rawValue)
                    Text("Quand ça compte").tag(YumiTalk.discreet.rawValue)
                    Text("Volontiers").tag(YumiTalk.chatty.rawValue)
                }
            } header: {
                Text("Caractère")
            } footer: {
                SettingsHelp(loc("« Quand ça compte » : quelques fois par jour au plus. « Volontiers » : aussi pour dire bonjour."))
            }
        }
    }
}
