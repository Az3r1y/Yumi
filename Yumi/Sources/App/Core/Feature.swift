import Foundation

/// What the person can turn on or off in Réglages › Fonctions. Each one is read where it acts,
/// with `Feature.isOn`, so turning it off takes effect at once.
enum Feature: String, CaseIterable, Identifiable, Sendable {
    // Text (⌥T)
    case textSummary, textTone, textReply, textToEvent
    // The character
    case weatherOutfit, petting, batteryMood, bedtime
    // The folded island
    case quotaOnSide
    // Voice and images
    case imageText, voiceInput, voiceReplies
    // The agent
    case planDay, appleNotes, research
    // Claude Code
    case sessionSummary, testReactions

    var id: String { rawValue }
    var key: String { "feature.\(rawValue)" }

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case text, character, island, senses, agent, claude
        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: loc("Texte (⌥T)")
            case .character: loc("Personnage")
            case .island: loc("Île repliée")
            case .senses: loc("Voix et images")
            case .agent: loc("Agent")
            case .claude: "Claude Code"
            }
        }
    }

    var group: Group {
        switch self {
        case .textSummary, .textTone, .textReply, .textToEvent: .text
        case .weatherOutfit, .petting, .batteryMood, .bedtime: .character
        case .quotaOnSide: .island
        case .imageText, .voiceInput, .voiceReplies: .senses
        case .planDay, .appleNotes, .research: .agent
        case .sessionSummary, .testReactions: .claude
        }
    }

    /// Speaking aloud surprises: off until the person asks for it.
    var defaultOn: Bool { self != .voiceReplies }

    var title: String {
        switch self {
        case .textSummary: loc("Résumer")
        case .textTone: loc("Changer le ton")
        case .textReply: loc("Proposer une réponse")
        case .textToEvent: loc("Transformer en rappel ou en événement")
        case .weatherOutfit: loc("S'habiller selon la météo")
        case .petting: loc("Réagir quand on clique sur lui")
        case .batteryMood: loc("Avoir faim quand la batterie est faible")
        case .bedtime: loc("Bâiller le soir, rappeler d'aller dormir")
        case .quotaOnSide: loc("Afficher le quota Claude sur le côté")
        case .imageText: loc("Lire le texte d'une image glissée")
        case .voiceInput: loc("Parler à Yumi")
        case .voiceReplies: loc("Répondre à voix haute")
        case .planDay: loc("Préparer ma journée")
        case .appleNotes: loc("Créer des notes dans Notes")
        case .research: loc("Recherche sur le web")
        case .sessionSummary: loc("Résumer une session terminée")
        case .testReactions: loc("Réagir aux tests")
        }
    }

    var detail: String {
        switch self {
        case .textSummary: loc("Quelques lignes pour un long texte sélectionné.")
        case .textTone: loc("Plus formel, plus court ou plus amical.")
        case .textReply: loc("Un brouillon de réponse à un message sélectionné.")
        case .textToEvent: loc("« Réunion jeudi 15 h » devient un événement prêt à ajouter, après ton accord.")
        case .weatherOutfit: loc("Lunettes de soleil quand il fait beau, nuage quand il pleut.")
        case .petting: loc("Un clic sur Yumi : un clin d'œil ou un cœur.")
        case .batteryMood: loc("Il a faim sous 15 %, il est content quand tu branches le chargeur.")
        case .bedtime: loc("Il bâille après 22 h, et après minuit il te dit d'aller dormir.")
        case .quotaOnSide: loc("« 5 h · 65 % » dans l'île repliée quand rien de plus important ne s'y passe.")
        case .imageText: loc("Glisse une image ou une capture sur Yumi : il en lit le texte, à corriger, traduire ou résumer.")
        case .voiceInput: loc("Tape ⌥V, parle, retape ⌥V : Yumi s'en occupe. Tout est transcrit sur le Mac.")
        case .voiceReplies: loc("Yumi lit ses réponses avec la voix du Mac.")
        case .planDay: loc("« Prépare ma journée » : l'agenda et les rappels du jour, et un plan proposé.")
        case .appleNotes: loc("« Note que… » crée une note dans l'app Notes, après ton accord.")
        case .research: loc("« Recherche » dans l'île : une question, une réponse courte et ses sources, par Gemini (Antigravity) ou Claude.")
        case .sessionSummary: loc("Une phrase dans l'encoche quand une session Claude Code se termine.")
        case .testReactions: loc("Yumi fête des tests qui passent, et a le tournis quand ils échouent.")
        }
    }

    static func isOn(_ feature: Feature, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: feature.key) as? Bool ?? feature.defaultOn
    }
}
