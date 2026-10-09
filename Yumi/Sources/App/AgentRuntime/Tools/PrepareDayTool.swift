import Foundation

/// "Prépare ma journée": reads the day (appointments, reminders, Notion tasks, weather) the way
/// `GetTodayTool` does, then asks the engine for a short plan. Reads only, changes nothing: the
/// person keeps the plan or not. Without an engine that answers, the day is listed as it is.
struct PrepareDayTool: Tool {
    var source: any TodaySource
    /// The engine that writes the plan (the one of the settings).
    var writer: any LLMProvider
    var calendar: Calendar = .current

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "prepare_day",
            name: loc("Prepare the day"),
            description: "Proposes a plan for the person's day from their appointments, reminders and tasks; use it when the person asks to prepare, organise or plan their day.",
            inputSchema: ToolInputSchema(fields: []),
            risk: .read,
            outputKeys: ["reply"])
    }

    func check(_ arguments: ToolArguments) async -> String? {
        Feature.isOn(.planDay) ? nil : loc("« Préparer ma journée » est coupé dans Réglages › Fonctions")
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        if let refused = await check(arguments) { throw ToolError.unavailable(refused) }
        let facts = await source.facts(now: context.now)
        let day = Self.list(facts, calendar: calendar)
        guard !day.isEmpty else {
            return ToolOutput(summary: "Nothing planned today.", values: ["reply": .string(loc("Rien de prévu aujourd'hui : ta journée est à toi."))])
        }
        let request = LLMRequest(
            system: """
                Tu es Yumi, un petit assistant. À partir de la liste de la journée donnée, propose un plan court et concret \
                en français : dans l'ordre de la journée, en gardant les rendez-vous à leur heure et en plaçant les rappels \
                et les tâches dans les moments libres. Cinq à huit lignes au plus, sans titre, sans inventer de rendez-vous.
                """,
            messages: [LLMMessage(role: .user, content: "Maintenant : \(FrenchText.clock(context.now, calendar: calendar)).\n" + day.joined(separator: "\n"))],
            expectsJSON: false, maxOutputTokens: 500)
        let plan = (try? await writer.complete(request).text.nonEmptyTrimmed) ?? nil
        let reply = plan ?? loc("Voici ta journée :") + "\n" + day.joined(separator: "\n")
        return ToolOutput(summary: "Prepared the day.", values: ["reply": .string(reply)])
    }

    /// The day, one line per thing, soonest first.
    static func list(_ facts: TodayFacts, calendar: Calendar) -> [String] {
        var lines: [String] = []
        for event in (facts.events ?? []).sorted(by: { $0.start < $1.start }) {
            lines.append("\(FrenchText.clock(event.start, calendar: calendar))–\(FrenchText.clock(event.end, calendar: calendar)) \(event.title)")
        }
        for reminder in facts.reminders ?? [] {
            let at = reminder.hasTime ? reminder.due.map { " (\(FrenchText.clock($0, calendar: calendar)))" } ?? "" : ""
            lines.append(loc("Rappel : \(reminder.title)") + at)
        }
        for task in facts.notionTasks ?? [] { lines.append(loc("Tâche : \(task.title)")) }
        return lines
    }
}
