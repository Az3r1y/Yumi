import Foundation

/// What the modules already know about today. nil means the module is off or has no access:
/// it is left out, not reported as empty.
struct TodayFacts: Equatable, Sendable {
    /// Today's appointments still to come, the all-day ones aside, soonest first.
    var events: [AgendaEvent]?
    /// Incomplete reminders due today.
    var reminders: [ReminderItem]?
    var weather: WeatherReport?
}

/// Reads `TodayFacts` from the modules, on demand. Implemented by the modules' bridge.
protocol TodaySource: Sendable {
    func facts(now: Date) async -> TodayFacts
}

/// "What do I have today?": the next appointments, today's reminders and the weather, from what
/// the modules already hold. Reads nothing new, changes nothing, sends nothing.
struct GetTodayTool: Tool {
    var source: any TodaySource
    var calendar: Calendar = .current

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "get_today",
            name: "Sum up today",
            description: "Sums up the person's day in one or two sentences: the next appointments of today, today's reminders and the current weather, from what Yumi's modules already show.",
            inputSchema: .empty,
            risk: .read,
            outputKeys: ["reply"])
    }

    /// Yumi reading its own modules: what the island already shows.
    func action(for arguments: ToolArguments) -> ToolAction? {
        ToolAction(kind: .read, resources: [ResourceRef(.yumi, "modules")], reversible: true)
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let facts = await source.facts(now: context.now)
        try Task.checkCancellation()
        let reply = TodayPhrase.reply(facts, now: context.now, calendar: calendar)
        return ToolOutput(summary: reply, values: ["reply": .string(reply)])
    }

    /// The answer is said, not listed: one or two sentences on one line.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let reply)? = output.values["reply"], !reply.isEmpty else { return "la réponse est vide" }
        if reply.contains(where: \.isNewline) || reply.hasPrefix("-") || reply.contains("•") { return "la réponse est une liste" }
        // A sentence ends with a stop followed by a space or the end: "v1.2" is not two.
        let ends = reply.matches(of: /[.!?](\s|$)/).count
        return ends > 2 ? "la réponse fait plus de deux phrases" : nil
    }
}

/// The day said in Yumi's voice: one or two sentences, never a list.
enum TodayPhrase {
    static func reply(_ facts: TodayFacts, now: Date, calendar: Calendar = .current) -> String {
        let first = [agenda(facts.events, calendar: calendar), reminders(facts.reminders)].compactMap { $0 }
        var sentences: [String] = []
        if !first.isEmpty { sentences.append(FrenchText.sentenceStart(first.joined(separator: ", et ")) + ".") }
        if let weather = facts.weather {
            sentences.append("Dehors, \(Int(weather.temperature.rounded()))° et \(WeatherSummary.sky(weather.code)).")
        }
        if sentences.isEmpty {
            return "Je ne vois ni ton agenda, ni tes rappels, ni la météo. Active-les dans mes réglages et je te dirai."
        }
        return sentences.joined(separator: " ")
    }

    private static func agenda(_ events: [AgendaEvent]?, calendar: Calendar) -> String? {
        guard let events else { return nil }
        guard let next = events.first else { return "plus aucun rendez-vous aujourd'hui" }
        let what = "\(oneLine(next.title)) à \(FrenchText.clock(next.start, calendar: calendar))"
        if events.count == 1 { return "encore un rendez-vous aujourd'hui : \(what)" }
        return "encore \(FrenchText.spelled(events.count)) rendez-vous aujourd'hui, le prochain c'est \(what)"
    }

    private static func reminders(_ reminders: [ReminderItem]?) -> String? {
        guard let reminders else { return nil }
        guard let first = NotesSummary.ordered(reminders).first else { return "aucun rappel" }
        if reminders.count == 1 { return "un rappel : \(oneLine(first.title))" }
        return "\(FrenchText.spelledCount(reminders.count, "rappel", "rappels")), dont \(oneLine(first.title))"
    }

    private static func oneLine(_ text: String) -> String {
        ApprovalRequest.oneLine(text, limit: 60) ?? "sans titre"
    }
}
