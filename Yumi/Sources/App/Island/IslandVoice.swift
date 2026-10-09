import AVFoundation
import Speech
import SwiftUI

// Talking to Yumi (Réglages › Fonctions › Voix et images): ⌥V or the microphone of the chat
// starts listening, the words show in the field as they come, ⌥V again sends them like a typed
// message. The voice is transcribed on the Mac only: a language the Mac cannot transcribe by
// itself is refused rather than sent away. Yumi can also read his answers aloud.

@MainActor
final class VoiceInput: ObservableObject {
    static let shared = VoiceInput()

    @Published private(set) var listening = false
    /// What was understood so far.
    @Published private(set) var heard = ""
    /// Why listening could not start or stopped.
    @Published private(set) var problem: String?

    /// A dictation never runs forever.
    private static let longest: Duration = .seconds(60)

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var limit: Task<Void, Never>?

    func toggle() {
        if listening { stop(send: true) } else { Task { await start() } }
    }

    func start() async {
        guard Feature.isOn(.voiceInput), !listening else { return }
        problem = nil
        guard await Self.allowed() else {
            problem = loc("Il me faut le micro et la reconnaissance vocale : Réglages Système › Confidentialité et sécurité.")
            return
        }
        let locale = Locale(identifier: AppLanguage.isEnglish ? "en-US" : "fr-FR")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            problem = loc("La reconnaissance vocale n'est pas disponible.")
            return
        }
        // Only on the Mac: never sent to Apple's servers
        guard recognizer.supportsOnDeviceRecognition else {
            problem = loc("Ton Mac ne sait pas transcrire cette langue sans internet : ajoute la dictée dans Réglages Système › Clavier.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        nonisolated(unsafe) let feed = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in feed.append(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            problem = loc("Le micro ne répond pas.")
            return
        }
        self.request = request
        heard = ""
        listening = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil && result == nil
            Task { @MainActor in
                guard let self, self.listening else { return }
                if let text { self.heard = text }
                if failed { self.stop(send: false) }
            }
        }
        limit = Task { [weak self] in
            try? await Task.sleep(for: Self.longest)
            guard !Task.isCancelled else { return }
            self?.stop(send: true)
        }
    }

    /// Stops listening; what was heard goes to the chat when `send` is true.
    func stop(send: Bool) {
        guard listening else { return }
        limit?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        request = nil
        recognition = nil
        listening = false
        let text = heard
        heard = ""
        if send, text.nonEmptyTrimmed != nil { IslandActions.send(text) }
    }

    private static func allowed() async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        return microphone && speech
    }
}
