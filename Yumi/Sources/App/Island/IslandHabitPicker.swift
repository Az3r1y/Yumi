import SwiftUI

// What Yumi holds while an agent works (YumiWorkHabit), chosen at the first launch and in the
// settings: a small animated Yumi showing the choice, and a row of chips that scrolls.

/// A small Yumi doing the habit of a choice. The random one shows a new habit every four seconds.
struct WorkHabitPreview: View {
    let choice: YumiWorkHabit
    var size: CGFloat = 44
    @StateObject private var engine = BotEngine()

    var body: some View {
        YumiStage(engine: engine, followsPointer: false)
            .frame(width: size / 0.6, height: size / 0.6)
            .task(id: choice) {
                engine.setHabit(choice.habit(filming: IslandStudio.isOn))
                guard choice == .random else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    engine.setHabit(choice.habit(filming: IslandStudio.isOn))
                }
            }
            .accessibilityHidden(true)
    }
}

/// The chips of the island: one per choice, in a horizontal scroll.
struct WorkHabitChips: View {
    let choices: [YumiWorkHabit]
    let selected: String
    let choose: (YumiWorkHabit) -> Void
    @Environment(\.islandAccent) private var accent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(choices, id: \.self) { choice in
                    let on = selected == choice.rawValue
                    Button { choose(choice) } label: {
                        Text(choice.label)
                            .font(IslandTheme.text(11, on ? .semibold : .medium))
                            .foregroundStyle(on ? Color.white : IslandCardTheme.mute)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .overlay(Capsule().strokeBorder(on ? accent : IslandCardTheme.chipLine, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
