import SwiftUI

// The first launch: Yumi asks the person's first name, in his voice, with a single field
// (design/yumi/voix.md). The answer goes to the core through `memorySetName`. It can be
// passed over; he asks again later, without insisting.

struct WelcomeActivity: View {
    @State private var text = ""
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
            TextButton(label: "Plus tard") { IslandActions.skipName() }
                .riseIn(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focused = true }
    }

    private func answer() {
        guard let name = FirstName.clean(text) else { return }
        IslandActions.giveName(name)
    }
}
