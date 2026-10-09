import Foundation
import Testing

// What Yumi reads aloud, and the shortcut of the voice.

@Suite @MainActor struct SpeakingTests {
    @Test func onlyWordsAreReadAloud() {
        let answer = """
            Voici **le plan** :
            - [la doc](https://example.com/doc)
            ```swift
            let x = 1
            ```
            C'est tout.
            """
        let spoken = VoiceReplies.plain(answer)
        #expect(spoken.contains("Voici le plan"))
        #expect(spoken.contains("la doc"))
        #expect(!spoken.contains("https"))
        #expect(!spoken.contains("let x"))
        #expect(!spoken.contains("*"))
        #expect(spoken.hasSuffix("C'est tout."))
    }

    @Test func theVoiceShortcutFollowsItsSwitch() throws {
        let defaults = try #require(UserDefaults(suiteName: "voice-\(UUID().uuidString)"))
        #expect(QuickTaskShortcut.stored(defaults, QuickTaskShortcut.voice)?.keyCode == 9)
        defaults.set(false, forKey: Feature.voiceInput.key)
        #expect(QuickTaskShortcut.stored(defaults, QuickTaskShortcut.voice) == nil)
    }
}
