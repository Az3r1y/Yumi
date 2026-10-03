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
        case .completed:
            return YumiRemark(id: "agent-\(result.runID)", text: "C'est fait, et j'ai vérifié\(goal).", mood: .happy, duration: 6)
        case .partial:
            return YumiRemark(id: "agent-\(result.runID)", text: "C'est fait en partie\(goal) : une étape facultative a été laissée.",
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

    private static func failure(_ error: AgentError?) -> String {
        switch error {
        case .busy?: "Je suis déjà sur une autre tâche. Redemande-moi juste après."
        case .noProvider?: "Je n'ai pas de modèle pour réfléchir : ajoute une clé Anthropic dans les réglages."
        case .providerFailed?: "Le modèle ne m'a pas répondu. Rien n'a été fait."
        case .unsupportedAction?: "Je ne sais pas encore faire ça, alors je n'ai rien touché. Pour l'instant je sais seulement créer un fichier sur ton Bureau ou dans Documents."
        case .cannotPlan?, .invalidPlan?: "Je ne sais pas encore faire ça. Rien n'a été fait."
        case .verificationFailed?: "J'ai essayé, mais le résultat n'est pas celui attendu."
        case .invalidArguments?: "Je n'ai pas pu : l'emplacement ou le fichier ne convient pas (le détail est dans les réglages)."
        default: "Ça n'a pas marché."
        }
    }
}
