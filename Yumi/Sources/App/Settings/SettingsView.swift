import SwiftUI
import AppKit

// The settings window: a sidebar of pages, each a grouped form (Settings/). The keys stay the
// ones of the old window, so nothing set before is lost (`SettingsPage.settings`).

struct SettingsView: View {
    @AppStorage(SettingsPage.developerKey) private var developer = false
    @State private var selection: SettingsPage?

    init(page: SettingsPage = .general) {
        _selection = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.sidebar(developer: developer), selection: $selection) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            page(SettingsPage.shown(selection, developer: developer))
                .formStyle(.grouped)
                .navigationTitle(SettingsPage.shown(selection, developer: developer).title)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 480, idealHeight: 600)
        .onChange(of: selection) { _, page in
            // Option and a click on "À propos" show the developer tools
            if page == .about, NSEvent.modifierFlags.contains(.option) { developer = true }
        }
    }

    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general:     GeneralSettings()
        case .yumi:        YumiSettings()
        case .features:    FeaturesSettings()
        case .modules:     ModulesSettings()
        case .engines:     EnginesSettings()
        case .claudeCode:  ClaudeCodeSettings()
        case .permissions: PermissionsSettings()
        case .memory:      MemorySettings()
        case .about:       AboutSettings()
        case .developer:   DeveloperSettings()
        }
    }
}

// MARK: - Shared pieces

/// A state at a glance: a coloured symbol and a few words.
struct SettingsStatus: View {
    enum Tone { case ok, warning, off }
    let text: String
    let tone: Tone

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: tone == .ok ? "checkmark.circle.fill" : tone == .warning ? "exclamationmark.triangle.fill" : "circle.dashed")
                .foregroundStyle(tone == .ok ? Color.green : tone == .warning ? Color.orange : Color.secondary)
        }
        .font(.callout)
    }
}

/// The grey sentence under a setting, only where it helps.
struct SettingsHelp: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            // A shortcut already held by Yumi (⌥ Espace) would never reach the recorder.
            NotificationCenter.default.post(name: .shortcutRecording, object: true)
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                // Escape alone stops recording and keeps the shortcut.
                if mods.isEmpty, event.keyCode == 53 {
                    DispatchQueue.main.async {
                        self.isRecording = false
                        if let t = token { NSEvent.removeMonitor(t) }
                        NotificationCenter.default.post(name: .shortcutRecording, object: false)
                    }
                    return nil
                }
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                    NotificationCenter.default.post(name: .shortcutRecording, object: false)
                }
                return nil
            }
        } label: {
            Text(isRecording ? loc("Appuie sur les touches…") : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? loc("Aucun") : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:loc("Espace"), 50:"`", 27:"-", 24:"=",
            18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 29:"0",
            36:"↩", 48:"⇥", 33:"[", 30:"]", 41:";", 39:"'", 43:",", 47:".", 44:"/", 42:"\\",
        ]
        return map[c] ?? "·"
    }
}
