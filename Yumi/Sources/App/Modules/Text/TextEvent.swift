import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A reminder or an appointment found in a text by Apple Intelligence's model, to add through
/// the agent (`AddReminderTool`, `AddEventTool`): the same approval and check as when asked in
/// words.
struct TextEvent: Equatable, Sendable {
    var title: String
    /// "YYYY-MM-DD", nil when the text gives no day.
    var date: String?
    /// "HH:mm", nil when the text gives no hour.
    var time: String?

    /// With a day and an hour it is an appointment, otherwise a reminder.
    var isAppointment: Bool { date != nil && time != nil }

    /// The plan the agent runs: one step, asked before anything is written.
    func plan() -> (AgentPlan, AgentRequest) {
        var arguments: ToolArguments = ["title": .string(title)]
        if let date { arguments["date"] = .string(date) }
        if let time { arguments["time"] = .string(time) }
        let toolID = isAppointment ? "add_event" : "add_reminder"
        let intent = isAppointment ? loc("Ajouter « \(title) » au calendrier") : loc("Ajouter « \(title) » à Rappels")
        let step = AgentStep(id: "step-1", description: intent, toolID: toolID, arguments: arguments, requiresApproval: true)
        return (AgentPlan(goal: intent, steps: [step], estimatedRisk: .write, requiredTools: [toolID], plannedBy: "island"),
                AgentRequest(userIntent: intent))
    }

    /// The model's fields, kept only when they have the expected form.
    static func checked(title: String, date: String, time: String) -> TextEvent? {
        guard let title = title.nonEmptyTrimmed else { return nil }
        let day = date.trimmingCharacters(in: .whitespaces)
        let hour = time.trimmingCharacters(in: .whitespaces)
        let validDay = day.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil ? day : nil
        let validHour = hour.wholeMatch(of: /([01]\d|2[0-3]):[0-5]\d/) != nil ? hour : nil
        return TextEvent(title: title, date: validDay, time: validDay == nil ? nil : validHour)
    }

    /// What the model finds in the text, read against `now`; nil when there is nothing to plan.
    static func find(in text: String, now: Date = Date()) async -> TextEvent? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), TextAI.isAvailable else { return nil }
        let today = now.formatted(.iso8601.year().month().day())
        let weekday = now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
        let session = LanguageModelSession(instructions: """
            Tu trouves dans le texte donné une chose à faire ou un rendez-vous. Nous sommes le \\(weekday) \\(today). \\
            Donne un titre court, la date au format AAAA-MM-JJ et l'heure au format HH:mm, \\
            ou des champs vides quand le texte ne les donne pas. N'invente ni date ni heure.
            """)
        guard let draft = try? await session.respond(to: text, generating: Draft.self).content else { return nil }
        return checked(title: draft.title, date: draft.date, time: draft.time)
        #else
        return nil
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct Draft {
    @Guide(description: "titre court de la chose à faire ou du rendez-vous")
    var title: String
    @Guide(description: "date au format AAAA-MM-JJ, ou vide")
    var date: String
    @Guide(description: "heure au format HH:mm sur 24 heures, ou vide")
    var time: String
}
#endif
