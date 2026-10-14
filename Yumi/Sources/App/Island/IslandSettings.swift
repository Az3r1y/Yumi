import AppKit
import SwiftUI

// The everyday settings, without leaving the island (`.set` in the mock-up): sounds and
// their volume, how long before the island folds back, and what he holds while an agent
// works. They act at once.

struct SettingsActivity: View {
    @ObservedObject var state: AppState
    @AppStorage(IslandPrefs.workHabitKey) private var workHabit = YumiWorkHabit.current().rawValue
    @State private var githubToken = ""
    @ObservedObject private var updates = YumiUpdates.shared
    @State private var githubConnected = IslandActions.githubConnected
    /// How much he speaks first (Contracts/RemarkTypes.swift).
    @AppStorage(YumiTalk.defaultsKey) private var talk = YumiTalk.discreet.rawValue
    /// The sounds, the folding, GitHub and the versions wait behind "Plus de réglages".
    @State private var more = false
    private static let talks: [(value: YumiTalk, label: String)] =
        [(.silent, loc("Silencieux")), (.discreet, loc("Discret")), (.chatty, loc("Bavard"))]

    /// `foldDelay`: seconds, 0 for never.
    private static let delays: [(seconds: TimeInterval, label: String)] =
        [(5, "5 s"), (15, "15 s"), (30, "30 s"), (60, "1 min"), (0, loc("Jamais"))]

    var body: some View {
        VStack(spacing: 9) {
            row(loc("Couleur")) { AccentSwatches() }
                .riseIn(0)
            HStack(spacing: 12) {
                Text("Skin")
                    .font(IslandTheme.text(12.5, .medium))
                    .foregroundStyle(IslandTheme.fg)
                Spacer(minLength: 0)
                // One row that scrolls: every costume, without making the island taller
                ScrollView(.horizontal, showsIndicators: false) { CostumeChips(oneRow: true) }
                    .frame(maxWidth: 330)
            }
            .riseIn(1)
            row(loc("Habitude")) {
                HStack(spacing: 4) {
                    WorkHabitChips(choices: YumiWorkHabit.settingsChoices, selected: workHabit) { choice in
                        workHabit = choice.rawValue
                        IslandActions.tap()
                    }
                    .frame(maxWidth: 300)
                    WorkHabitPreview(choice: YumiWorkHabit(rawValue: workHabit) ?? .coffee, size: 18)
                        .frame(width: 30, height: 22)
                }
            }
            .riseIn(2)
            row(loc("Yumi parle")) {
                HStack(spacing: 0) {
                    ForEach(Self.talks, id: \.value) { choice in
                        SegmentButton(label: choice.label, on: talk == choice.value.rawValue) {
                            talk = choice.value.rawValue
                            IslandActions.tap()
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(3)
            HStack(spacing: 14) {
                if let newer = updates.newer {
                    TextButton(label: loc("\(newer.tag) est là")) { updates.openRelease() }
                }
                Spacer(minLength: 0)
                // Sounds, folding, modules and their accounts (GitHub, Gmail, Notion): the app's settings
                TextButton(label: loc("Tous les réglages")) { IslandActions.openSettings() }
                TextButton(label: loc("Modules et comptes")) { IslandActions.openSettings(.modules) }
            }
            .riseIn(4)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
    }

    private func connectGitHub() {
        guard let token = GitHubFigures.cleanToken(githubToken) else { return }
        IslandActions.connectGitHub(token)
        githubToken = ""
        githubConnected = true
    }

    /// The choice that matches the stored delay; an older value falls on the nearest one.
    private var selected: TimeInterval {
        let value = state.autoCloseInterval
        if value <= 0 { return 0 }
        return Self.delays.filter { $0.seconds > 0 }.min { abs($0.seconds - value) < abs($1.seconds - value) }?.seconds ?? 15
    }

    /// `.srow`
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(IslandTheme.text(12.5, .medium))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 10) { control() }
        }
    }
}

/// `.tgl`
struct IslandToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            isOn.toggle()
            IslandActions.tap()
        } label: {
            Capsule()
                .fill(isOn ? IslandTheme.green : Color.white.opacity(0.2))
                .frame(width: 34, height: 20)
                .overlay(alignment: .leading) {
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .offset(x: isOn ? 16 : 2)
                }
                .animation(.islandSpring(0.25), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? loc("activé") : loc("désactivé"))
    }
}

/// `.seg button`
struct SegmentButton: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(IslandTheme.text(11, .semibold))
                .monospacedDigit()
                .foregroundStyle(on ? Color.white : IslandTheme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(on ? 0.22 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
