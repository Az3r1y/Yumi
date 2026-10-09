import AVFoundation
import Foundation

/// Yumi's answers read aloud with the Mac's voice, when the person turned it on.
@MainActor
enum VoiceReplies {
    private static let synthesizer = AVSpeechSynthesizer()

    static func say(_ text: String) {
        guard Feature.isOn(.voiceReplies) else { return }
        let spoken = plain(text)
        guard !spoken.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = AVSpeechSynthesisVoice(language: AppLanguage.isEnglish ? "en-US" : "fr-FR")
        synthesizer.speak(utterance)
    }

    static func hush() { synthesizer.stopSpeaking(at: .immediate) }

    /// The words without Markdown, code or links: what makes sense out loud.
    static func plain(_ text: String) -> String {
        var spoken = text.replacing(/```[\s\S]*?```/, with: "")
        spoken = spoken.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
        spoken = spoken.replacing(/https?:\/\/\S+/, with: "")
        spoken = spoken.replacing(/[*_`#>|]/, with: "")
        return spoken.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: ". ")
            .replacing(/\.\s*\./, with: ".")
    }
}
