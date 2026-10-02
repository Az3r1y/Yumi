import SwiftUI

// The everyday settings, without leaving the island (`.set` in the mock-up): sounds and
// their volume, how long before the island folds back, and the cigarette. They act at once.

struct SettingsActivity: View {
    @ObservedObject var state: AppState
    @AppStorage(IslandPrefs.smokeKey) private var smokes = true

    /// `foldDelay`: seconds, 0 for never.
    private static let delays: [(seconds: TimeInterval, label: String)] =
        [(5, "5 s"), (15, "15 s"), (30, "30 s"), (60, "1 min"), (0, "Jamais")]

    var body: some View {
        VStack(spacing: 9) {
            row("Sons") {
                Slider(value: $state.soundVolume, in: 0...0.2) { editing in
                    if !editing { SoundEngine.shared.play("pop") }
                }
                .controlSize(.mini)
                .tint(.white)
                .frame(width: 96)
                .disabled(!state.soundEnabled)
                .opacity(state.soundEnabled ? 1 : 0.35)
                .accessibilityLabel("Volume")
                IslandToggle(isOn: $state.soundEnabled, label: "Sons")
            }
            .riseIn(0)
            row("Repli de l'île après") {
                HStack(spacing: 0) {
                    ForEach(Self.delays, id: \.seconds) { delay in
                        SegmentButton(label: delay.label, on: selected == delay.seconds) {
                            state.autoCloseInterval = delay.seconds
                            IslandActions.tap()
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(1)
            row("Cigarette quand un agent travaille") {
                IslandToggle(isOn: $smokes, label: "Cigarette")
            }
            .riseIn(2)
            row("Ce que je sais de toi") {
                TextButton(label: state.memory.isEmpty ? "Voir" : "Voir (\(state.memory.count))") { IslandActions.go(.memory) }
            }
            .riseIn(3)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
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
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }
}

/// `.seg button`
private struct SegmentButton: View {
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
