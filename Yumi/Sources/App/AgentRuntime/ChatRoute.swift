import Foundation

/// Where a chat message goes. The runtime takes what changes something on the Mac, so that it
/// goes through the permissions and is verified; talking, questions and reading stay with the
/// chat. Decided from the plan the runtime accepted, never from the words of the message.
enum ChatRoute: Equatable, Sendable {
    /// Run this plan: it acts on the Mac.
    case agent(AgentPlan)
    /// A clear action on the Mac that Yumi cannot do: say so, do nothing, pass it to nobody.
    case blocked(String)
    /// A question about the person's calendar, reminders or free time that the runtime could not
    /// answer: Yumi says what he can do. Never the chat, which cannot read them and would only ask
    /// the person to paste their data. Carries why the runtime could not plan, if it knows.
    case agendaKeptFromChat(AgentError?)
    /// Answer as a conversation. The chat cannot change the Mac (ChatTools).
    case chat

    /// Tools that do their job without changing anything risky, but that only the runtime can
    /// run: a plan using one of them goes to the runtime too.
    static let runtimeTools: Set<String> = ["start_focus", "get_today"]

    static func route(_ planned: Result<AgentPlan, AgentError>) -> ChatRoute {
        switch planned {
        case .success(let plan) where plan.estimatedRisk >= .write || plan.requiredTools.contains(where: runtimeTools.contains): .agent(plan)
        case .failure(.unsupportedAction(let reason)): .blocked(reason)
        default: .chat
        }
    }

    /// The same, and a message about the person's agenda never goes to the chat.
    static func route(_ planned: Result<AgentPlan, AgentError>?, message: String) -> ChatRoute {
        let route = planned.map(route) ?? .chat
        guard route == .chat, isPersonalAgenda(message) else { return route }
        if case .failure(let error)? = planned { return .agendaKeptFromChat(error) }
        return .agendaKeptFromChat(nil)
    }

    /// "Qu'est-ce que j'ai demain ?", "combien de temps libre jeudi", "mes rendez-vous de lundi".
    /// Only keeps a message away from the chat; it never makes anything run.
    static func isPersonalAgenda(_ message: String) -> Bool {
        let text = " " + message.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'") + " "
        let topics = ["agenda", "calendrier", "rendez-vous", "rendez vous", " rdv", "reunion", "rappel", "temps libre",
                      "creneau", "dispo", "planning", "emploi du temps", "occupe", "libre "]
        let personal = [" mon ", " ma ", " mes ", "j'ai", "je suis", " moi", " m'", "ai-je", "suis-je", " je "]
        if topics.contains(where: text.contains), personal.contains(where: text.contains) { return true }
        let asks = ["qu'est-ce que j'ai", "qu'est ce que j'ai", "qu'ai-je", "j'ai quoi", "j ai quoi", "qu'est-ce qui m'attend"]
        let days = ["aujourd'hui", "demain", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
                    "ce soir", "ce matin", "cet apres-midi", "semaine", "week-end", "prevu"]
        if asks.contains(where: text.contains) && days.contains(where: text.contains) { return true }
        return isPersonalAgendaInEnglish(text)
    }

    /// "What do I have tomorrow?", "how much free time on Thursday", "my appointments on Monday".
    private static func isPersonalAgendaInEnglish(_ text: String) -> Bool {
        let topics = ["calendar", "agenda", "appointment", "meeting", "reminder", "free time", "schedule", "busy", "available",
                      "slot", "plans "]
        let personal = [" my ", " i ", " i'm ", " am i ", " me ", " do i ", " have i "]
        if topics.contains(where: text.contains), personal.contains(where: text.contains) { return true }
        let asks = ["what do i have", "what have i got", "what's on", "whats on", "what is on", "anything on", "what's planned"]
        let days = ["today", "tomorrow", "tonight", "this morning", "this afternoon", "this evening", "monday", "tuesday",
                    "wednesday", "thursday", "friday", "saturday", "sunday", "this week", "weekend", "next week"]
        return asks.contains(where: text.contains) && days.contains(where: text.contains)
    }
}
