import SwiftUI

// The first launch: Yumi asks the person's first name, in his voice, with a single field
// (design/yumi/voix.md), and what he should have in hand while an agent works: coffee,
// cigarette or matcha. The name goes to the core through `memorySetName`; it can be passed
// over, he asks again later, without insisting. The choice is made before the name is sent.

struct WelcomeActivity: View {
    @State private var text = ""
    /// Empty until the person picks one.
    @State private var held = YumiWorkHabit.isChosen() ? YumiWorkHabit.current().rawValue : ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ActTitle(text: "Moi, c'est Yumi. Et toi ?").riseIn(0)
                ActSub(text: "Juste ton prénom. Je le garde pour moi.").riseIn(1)
            }
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Ton prénom").foregroundStyle(IslandTheme.faint))
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .focused($focused)
                    .onSubmit(answer)
                RoundButton(style: .white, symbol: "arrow.up", label: "Valider", small: true, action: answer)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(2)
            HStack(spacing: 8) {
                ActSub(text: "Quand un agent bosse, je prends")
                HStack(spacing: 0) {
                    ForEach(YumiWorkHabit.firstChoices, id: \.self) { choice in
                        SegmentButton(label: choice.label, on: held == choice.rawValue) { choose(choice) }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(3)
            TextButton(label: "Plus tard") { IslandActions.skipName() }
                .riseIn(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }

    private func choose(_ choice: YumiWorkHabit) {
        held = choice.rawValue
        UserDefaults.standard.set(choice.rawValue, forKey: YumiWorkHabit.defaultsKey)
        IslandActions.tap()
    }

    private func answer() {
        guard !held.isEmpty, let name = FirstName.clean(text) else { return }
        IslandActions.giveName(name)
    }
}
