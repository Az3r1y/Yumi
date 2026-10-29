import Foundation

/// The simple mode: Yumi without any model. It turns the requests `SimpleRequestParser`
/// understands into a plan for the same tools, and the plan goes through `PlanValidator`, the
/// permissions and the verification like any other. No network, nothing leaves the Mac.
struct SimplePlanner: AgentPlanner {
    static let engineName = "simple"

    var parser = SimpleRequestParser()
    /// Where a task goes: Reminders, or Notion when the person chose it (Réglages > Général).
    var taskDestination: @Sendable () -> (QuickTaskDestination, base: String?) = { (QuickTaskDestination.stored(), nil) }

    var name: String { Self.engineName }

    func propose(for request: AgentRequest, tools: [ToolDescriptor]) async throws(AgentError) -> PlanProposal {
        proposal(for: request.trimmedIntent, tools: tools.map(\.id))
    }

    /// The plan for this sentence, or `cannotPlan` when it is not one of the forms understood or
    /// the tool it needs is not there.
    func proposal(for sentence: String, tools: [String]) -> PlanProposal {
        guard let understood = parser.parse(sentence), let (goal, tool, arguments) = step(for: understood),
              tools.contains(tool) else {
            return PlanProposal(goal: nil, steps: nil, cannotPlan: "not understood by the simple mode", isAction: false,
                                engine: Self.engineName)
        }
        return PlanProposal(goal: goal, steps: [.init(description: goal, tool: tool, arguments: arguments, optional: nil, requiresApproval: nil)],
                            cannotPlan: nil, isAction: nil, engine: Self.engineName)
    }

    func step(for request: SimpleRequest) -> (goal: String, tool: String, arguments: ToolArguments)? {
        switch request {
        case .reminder(let draft):
            var arguments: ToolArguments = ["title": .string(draft.title)]
            if let date = draft.dateArgument { arguments["date"] = .string(date) }
            if let time = draft.timeArgument { arguments["time"] = .string(time) }
            return (loc("Ajouter le rappel « \(draft.title) »"), "add_reminder", arguments)
        case .task(let draft):
            let (destination, base) = taskDestination()
            var arguments: ToolArguments = ["title": .string(draft.title)]
            if let date = draft.dateArgument { arguments["date"] = .string(date) }
            switch destination {
            case .reminders:
                return (loc("Ajouter « \(draft.title) » à Rappels"), "add_reminder", arguments)
            case .notion:
                if let base { arguments["base"] = .string(base) }
                return (loc("Ajouter « \(draft.title) » à Notion"), "add_notion_task", arguments)
            }
        case .event(let title, let date, let time, let minutes):
            var arguments: ToolArguments = ["title": .string(title), "date": .string(date), "time": .string(time)]
            if let minutes { arguments["duration_minutes"] = .number(Double(minutes)) }
            return (loc("Ajouter « \(title) » à l'agenda"), "add_event", arguments)
        case .focus(let minutes):
            return (loc("Lancer un Focus de \(minutes) minutes"), "start_focus", ["minutes": .number(Double(minutes))])
        case .time:
            return (loc("Donner l'heure"), "get_current_time", [:])
        case .day(let date, let freeTime):
            var arguments: ToolArguments = [:]
            if let date { arguments["date"] = .string(date) }
            if freeTime { arguments["free_time"] = .bool(true) }
            return (loc("Résumer la journée"), "get_today", arguments)
        case .music(let command):
            return (command.goal, "control_music", ["action": .string(command.rawValue)])
        }
    }
}

/// What Yumi says when the simple mode did not understand: kind, with buttons to start again.
enum SimpleReply {
    static var notUnderstood: String {
        loc("Je n'ai pas bien compris, pardon. Sans IA, je sais déjà créer un rappel, ajouter une tâche, noter un rendez-vous, lancer un minuteur ou mettre ta musique. Par exemple : « rappelle-moi d'appeler maman demain 18 h ».")
    }

    static var plugLater: String {
        loc("Pour discuter de tout, tu pourras me brancher une IA dans les réglages, section Moteurs.")
    }

    static var suggestions: [ChatSuggestion] {
        [
            ChatSuggestion(label: loc("Rappel"), text: loc("Rappelle-moi de "), sends: false),
            ChatSuggestion(label: loc("Tâche"), text: loc("Nouvelle tâche : "), sends: false),
            ChatSuggestion(label: loc("Agenda"), text: loc("Qu'est-ce que j'ai aujourd'hui ?"), sends: true),
            ChatSuggestion(label: loc("Minuteur"), text: loc("Concentre-moi 25 min"), sends: true),
            ChatSuggestion(label: loc("Musique"), text: loc("Mets de la musique"), sends: true),
        ]
    }
}

/// A button under one of Yumi's messages: it starts a sentence in the field, or sends it.
struct ChatSuggestion: Equatable, Sendable, Identifiable {
    var label: String
    var text: String
    /// True: sent as is. False: put in the field, for the person to finish.
    var sends: Bool

    var id: String { label }
}

/// The planner of the app: the engine of the settings, and the simple mode whenever no model
/// can answer. The simple mode also takes over what a model could not plan but it understands
/// (a small model sometimes misses « rappelle-moi… »). Either way the plan is only a proposal.
struct EngineAgentPlanner: AgentPlanner {
    var llm: LLMAgentPlanner
    var simple: SimplePlanner
    /// The engine the person chose, nil for automatic.
    var choice: @Sendable () -> Engine?

    var name: String { "engine" }

    func propose(for request: AgentRequest, tools: [ToolDescriptor]) async throws(AgentError) -> PlanProposal {
        let fallback = simple.proposal(for: request.trimmedIntent, tools: tools.map(\.id))
        if choice() == .simple { return fallback }
        do {
            let proposal = try await llm.propose(for: request, tools: tools)
            // The model said it cannot plan (and it is not a refused action): the simple mode may know.
            if proposal.cannotPlan?.nonEmptyTrimmed != nil, proposal.isAction != true, fallback.steps != nil { return fallback }
            return proposal
        } catch .noProvider {
            return fallback
        } catch .cancelled {
            throw .cancelled
        } catch {
            if fallback.steps != nil { return fallback }
            throw error
        }
    }
}
