import Foundation

/// How Yumi looks and what he says while the agent runtime works, with the character's
/// existing vocabulary (moods, poses, remarks). The runtime only describes its activity;
/// this decides the look. No view, no state: the island applies it (`AgentReaction`).
struct AgentLook: Equatable, Sendable {
    var mood: YumiMood
    /// A one-off movement when the activity starts. nil for none.
    var pose: YumiPose?

    static func of(_ activity: AgentActivity) -> AgentLook {
        switch activity {
        case .idle: AgentLook(mood: .neutral)
        case .planning, .thinking: AgentLook(mood: .thinking)
        case .waiting: AgentLook(mood: .curious)
        case .working: AgentLook(mood: .focused, pose: .pop)
        case .checking: AgentLook(mood: .curious)
        case .success: AgentLook(mood: .happy, pose: .celebrate)
        case .error: AgentLook(mood: .worried, pose: .shake)
        }
    }

    /// What Yumi says when a run ends, or nil when there is nothing to say (the person
    /// cancelled it themselves). Built from the result, never from text a model wrote alone:
    /// the goal is quoted, the verdict is the runtime's.
    static func remark(for result: AgentResult) -> YumiRemark? {
        let goal = result.goal?.nonEmptyTrimmed.map { " (\($0))" } ?? ""
        switch result.status {
        case .completed where !replies(result).isEmpty:
            return YumiRemark(id: "agent-\(result.runID)", text: replies(result).joined(separator: " "), mood: .happy, duration: 8)
        case .completed:
            return YumiRemark(id: "agent-\(result.runID)", text: "C'est fait, et j'ai vérifié\(goal).", mood: .happy, duration: 6)
        case .partial:
            // A step left out because the person said no is said as such: it is not a success.
            let refused = result.steps.contains {
                if $0.status == .skipped, case .permissionDenied? = $0.error { true } else { false }
            }
            let left = refused ? "tu as refusé une étape, je l'ai laissée" : "une étape facultative a été laissée"
            return YumiRemark(id: "agent-\(result.runID)", text: "C'est fait en partie\(goal) : \(left).",
                              mood: .neutral, duration: 8)
        case .failed:
            return YumiRemark(id: "agent-\(result.runID)", text: failure(result.error), mood: .worried, duration: 8)
        case .cancelled:
            switch result.error {
            case .permissionDenied: return YumiRemark(id: "agent-\(result.runID)", text: "D'accord, je n'y touche pas.", mood: .neutral, duration: 4)
            case .approvalExpired: return YumiRemark(id: "agent-\(result.runID)", text: "Sans réponse, je n'ai rien fait.", mood: .neutral, duration: 6)
            default: return nil
            }
        }
    }

    /// What the tools said, in Yumi's voice, when every step that ran gave a reply. Written by
    /// the code of the tools after it checked its work, never by a model.
    private static func replies(_ result: AgentResult) -> [String] {
        let done = result.steps.filter { $0.status == .completed }
        let replies = done.compactMap { step -> String? in
            guard case .string(let reply)? = step.output?.values["reply"] else { return nil }
            return reply.nonEmptyTrimmed
        }
        return replies.count == done.count ? replies : []
    }

    /// What Yumi can do, said when he is asked something he cannot. The App Store build has no
    /// tool that changes anything.
    private static var unsupported: String {
        #if APPSTORE
        "Je ne sais pas faire ça dans cette version, alors je n'ai rien touché."
        #else
        "Je ne sais pas encore faire ça, alors je n'ai rien touché. Pour l'instant je sais créer un fichier (dans Téléchargements, sur ton Bureau ou dans Documents) et ajouter du texte à ceux que j'ai créés, ajouter un rappel ou un événement à ton calendrier, lancer un Focus et te dire ce que tu as aujourd'hui."
        #endif
    }

    static let busy = "Je suis déjà sur une autre tâche. Redemande-moi juste après."

    /// Said when a question about the person's agenda could not be answered: what Yumi can do,
    /// never an invitation to paste their data elsewhere.
    static func agendaKeptFromChat(_ error: AgentError?) -> String {
        switch error {
        case .noProvider?: return failure(error)
        case .cannotRun(_, let reason)?, .invalidArguments(_, let reason)?: return "Je ne peux pas : \(reason)."
        default:
            return "Je n'ai pas réussi à lire ça. Pour ton agenda, tes rappels et ton temps libre, demande-moi un jour précis, d'aujourd'hui à dans quatorze jours, par exemple « qu'est-ce que j'ai demain ? » ou « combien de temps libre jeudi ? »."
        }
    }

    private static func failure(_ error: AgentError?) -> String {
        switch error {
        case .busy?: "Je suis déjà sur une autre tâche. Redemande-moi juste après."
        case .noProvider?: "Je n'ai aucun moteur pour réfléchir : installe Claude Code et connecte-toi (claude, puis /login), ou ajoute une clé Anthropic, OpenAI ou Gemini, ou lance Ollama : réglages, section Moteurs."
        case .providerFailed?: "Le modèle ne m'a pas répondu. Rien n'a été fait."
        case .unsupportedAction?: unsupported
        case .cannotPlan?, .invalidPlan?: "Je ne sais pas encore faire ça. Rien n'a été fait."
        case .verificationFailed(let reason)?: "J'ai essayé, mais le résultat n'est pas celui attendu : \(reason)."
        case .cannotRun(_, let reason)?: "Je ne peux pas le faire, alors je ne t'ai rien demandé : \(reason)."
        case .invalidArguments(_, let reason)?, .toolFailed(_, let reason, _)?: "Je n'ai pas pu : \(reason)."
        // Refused by a rule or by the permission system itself, before anything ran.
        case .permissionDenied(_, let reason?)?: "\(reason) Je n'ai rien fait."
        case .permissionDenied?: "Je n'en ai pas le droit, alors je n'ai rien fait."
        // A write is never run twice: the effect may be there, the person must look.
        case .toolTimedOut?: "Ça a pris trop de temps. Je ne sais pas si c'est fait : regarde avant de me redemander."
        default: "Ça n'a pas marché."
        }
    }
}
