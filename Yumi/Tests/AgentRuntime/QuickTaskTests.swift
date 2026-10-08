import Testing
import Foundation

private let parisCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

/// Thursday 8 October 2026, 10:00 in Paris.
private let thursday = parisCalendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!

private func day(_ d: Int, month: Int = 10) -> DateComponents { DateComponents(year: 2026, month: month, day: d) }

/// Reading a simple date in a task typed in the quick field.
@Suite struct QuickTaskParserTests {
    private let parser = QuickTaskParser(calendar: parisCalendar, now: { thursday })

    @Test func frenchDays() {
        #expect(parser.parse("Acheter du pain demain") == QuickTaskDraft(title: "Acheter du pain", day: day(9)))
        #expect(parser.parse("Rendre le livre après-demain") == QuickTaskDraft(title: "Rendre le livre", day: day(10)))
        #expect(parser.parse("Arroser les plantes aujourd'hui") == QuickTaskDraft(title: "Arroser les plantes", day: day(8)))
        #expect(parser.parse("Réunion vendredi à 9h30") == QuickTaskDraft(title: "Réunion", day: day(9), hour: 9, minute: 30))
        #expect(parser.parse("Dentiste lundi prochain") == QuickTaskDraft(title: "Dentiste", day: day(12)))
    }

    @Test func aWeekdayOfTodayIsNextWeek() {
        #expect(parser.parse("Appeler Paul jeudi 15h") == QuickTaskDraft(title: "Appeler Paul", day: day(15), hour: 15, minute: 0))
    }

    @Test func englishDays() {
        #expect(parser.parse("Call mom tomorrow at 3pm") == QuickTaskDraft(title: "Call mom", day: day(9), hour: 15, minute: 0))
        #expect(parser.parse("Send the invoice on friday 10:15") == QuickTaskDraft(title: "Send the invoice", day: day(9), hour: 10, minute: 15))
    }

    @Test func aTimeAloneIsTodayOrTomorrow() {
        #expect(parser.parse("Sport 18h") == QuickTaskDraft(title: "Sport", day: day(8), hour: 18, minute: 0))
        // 8:00 has gone by at 10:00.
        #expect(parser.parse("Sport 8h") == QuickTaskDraft(title: "Sport", day: day(9), hour: 8, minute: 0))
    }

    @Test func withoutADateTheTextStaysWhole() {
        #expect(parser.parse("Payer le loyer") == QuickTaskDraft(title: "Payer le loyer"))
        #expect(parser.parse("Lire 20 pages") == QuickTaskDraft(title: "Lire 20 pages"))
        #expect(parser.parse("  demain ") == QuickTaskDraft(title: "demain"))
    }

    @Test func times() {
        #expect(QuickTaskParser.time("15h")! == (15, 0))
        #expect(QuickTaskParser.time("9h30")! == (9, 30))
        #expect(QuickTaskParser.time("10:15")! == (10, 15))
        #expect(QuickTaskParser.time("3pm")! == (15, 0))
        #expect(QuickTaskParser.time("12am")! == (0, 0))
        for wrong in ["25h", "1h5", "13pm", "h", "10:", "20", "chez"] { #expect(QuickTaskParser.time(wrong) == nil) }
    }

    @Test func arguments() {
        let draft = parser.parse("Réunion vendredi à 9h30")
        #expect(draft.dateArgument == "2026-10-09")
        #expect(draft.timeArgument == "09:30")
        #expect(parser.parse("Payer le loyer").dateArgument == nil)
    }
}

/// The shortcut, the destination, and the plan the quick field hands to the runtime.
@Suite struct QuickTaskSettingsTests {
    private func defaults() -> UserDefaults {
        let name = "quick-task-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func shortcutIsOptionSpaceByDefault() {
        let store = defaults()
        #expect(QuickTaskShortcut.stored(store) == QuickTaskShortcut(flags: 1 << 19, keyCode: 49))
        QuickTaskShortcut(flags: (1 << 20) | (1 << 17), keyCode: 45).store(store)
        #expect(QuickTaskShortcut.stored(store) == QuickTaskShortcut(flags: (1 << 20) | (1 << 17), keyCode: 45))
        store.set(false, forKey: QuickTaskShortcut.enabledKey)
        #expect(QuickTaskShortcut.stored(store) == nil)
    }

    @Test func shiftAloneIsNotAShortcut() {
        let store = defaults()
        #expect(!QuickTaskShortcut(flags: 1 << 17, keyCode: 0).isValid)
        QuickTaskShortcut(flags: 1 << 17, keyCode: 0).store(store)
        #expect(QuickTaskShortcut.stored(store) == .standard)
    }

    @Test func destination() {
        let store = defaults()
        #expect(QuickTaskDestination.stored(store) == .reminders)
        store.set("notion", forKey: QuickTaskDestination.defaultsKey)
        #expect(QuickTaskDestination.stored(store) == .notion)
        #expect(QuickTaskDestination.notionBase(among: ["Tâches"], store) == "Tâches")
        #expect(QuickTaskDestination.notionBase(among: ["Tâches", "Perso"], store) == nil)
        store.set("Perso", forKey: QuickTaskDestination.notionBaseKey)
        #expect(QuickTaskDestination.notionBase(among: ["Tâches", "Perso"], store) == "Perso")
        #expect(QuickTaskDestination.notionBase(among: ["Tâches", "Travail"], store) == nil)
        #expect(QuickTaskDestination.notionBase(among: [], store) == nil)
    }

    @Test func planForReminders() {
        let draft = QuickTaskDraft(title: "Appeler Paul", day: day(15), hour: 15, minute: 0)
        let (plan, _) = QuickTask.plan(draft, to: .reminders, base: nil)
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].toolID == "add_reminder")
        #expect(plan.steps[0].requiresApproval)
        #expect(plan.steps[0].arguments == ["title": .string("Appeler Paul"), "date": .string("2026-10-15"), "time": .string("15:00")])
    }

    @Test func planForNotionKeepsTheDayAndTheBase() {
        let draft = QuickTaskDraft(title: "Envoyer le devis", day: day(9), hour: 9, minute: 0)
        let (plan, _) = QuickTask.plan(draft, to: .notion, base: "Perso")
        #expect(plan.steps[0].toolID == "add_notion_task")
        #expect(plan.steps[0].arguments == ["title": .string("Envoyer le devis"), "date": .string("2026-10-09"), "base": .string("Perso")])
    }
}

private final class QuickNotion: NotionTaskStore, @unchecked Sendable {
    func baseNames() -> [String] { ["Perso", " Tâches"] }
    func baseID(named name: String) -> String? { ["Perso", " Tâches"].contains(name) ? "0123456789abcdef0123456789abcdef" : nil }
    func problem(base: String) async -> String? { nil }
    func create(title: String, day: Date?, base: String) async throws -> String { "page" }
    func title(ofPage id: String) async -> String? { nil }
}

/// The approval: a reminder on this Mac is medium, a Notion task leaves the Mac and is high.
@MainActor
@Suite struct QuickTaskApprovalTests {
    private func risk(_ tool: any Tool, _ arguments: ToolArguments) -> RiskLevel? {
        let request = AgentPermissionRequest(runID: UUID(), stepID: "step-1", goal: "g", reason: "r", toolID: tool.descriptor.id,
                                             toolName: tool.descriptor.name, risk: tool.descriptor.risk, arguments: arguments,
                                             action: tool.action(for: arguments), requiresApproval: true)
        return try? RiskAssessor(projectRoot: { _ in nil }).assess(request).get().risk
    }

    @Test func remindersIsMediumNotionIsHigh() {
        let draft = QuickTaskDraft(title: "Envoyer le devis", day: day(9))
        let reminders = AddReminderTool(store: FakeReminderStore(), calendar: parisCalendar, now: { thursday })
        let notion = AddNotionTaskTool(store: QuickNotion(), calendar: parisCalendar, now: { thursday })
        #expect(risk(reminders, QuickTask.plan(draft, to: .reminders, base: nil).0.steps[0].arguments) == .medium)
        #expect(risk(notion, QuickTask.plan(draft, to: .notion, base: "Perso").0.steps[0].arguments) == .high)
    }

    /// A Notion title that starts with a space (" Tâches") is still found.
    @Test func aBaseNamedWithASpaceIsFound() async {
        let notion = AddNotionTaskTool(store: QuickNotion(), calendar: parisCalendar, now: { thursday })
        let arguments = QuickTask.plan(QuickTaskDraft(title: "Appeler Paul", day: day(9)), to: .notion, base: " Tâches").0.steps[0].arguments
        #expect(await notion.check(arguments) == nil)
        #expect(notion.action(for: arguments) != nil)
    }

    @Test func theReminderIsAddedOnlyAfterTheApproval() async throws {
        let store = FakeReminderStore()
        var tools = ToolRegistry.standard
        try tools.register(AddReminderTool(store: store, calendar: parisCalendar, now: { thursday }))
        let refused = ScriptedPermissionManager([.decision(.denied(reason: nil))])
        let draft = QuickTaskDraft(title: "Appeler Paul", day: day(15), hour: 15, minute: 0)
        let (plan, request) = QuickTask.plan(draft, to: .reminders, base: nil)

        let denied = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: "{}")), tools: tools, permissions: refused,
                                  policy: AgentPolicy(maximumRisk: .write))
        #expect(await !denied.execute(plan, for: request).status.succeeded)
        #expect(store.all.isEmpty)

        let granted = ScriptedPermissionManager([.decision(.granted)])
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: "{}")), tools: tools, permissions: granted,
                                 policy: AgentPolicy(maximumRisk: .write))
        let result = await agent.execute(plan, for: request)
        #expect(result.status == .completed)
        #expect(granted.requests.map(\.toolID) == ["add_reminder"])
        #expect(store.all.map(\.title) == ["Appeler Paul"])
    }
}
