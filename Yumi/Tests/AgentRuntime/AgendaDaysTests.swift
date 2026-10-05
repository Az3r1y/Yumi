import Foundation
import Testing

// yumi/agenda-jours: "qu'est-ce que j'ai demain ?", "combien de temps libre jeudi ?".

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()
/// Monday 5 October 2026, 9:00 in Paris.
private let monday = paris.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ day: Int, _ from: Int, _ to: Int, allDay: Bool = false) -> AgendaEvent {
    AgendaEvent(id: title, title: title, start: at(day, from), end: at(day, to), isAllDay: allDay, location: "", joinURL: nil)
}

/// Facts per day, as the modules' bridge would read them.
private struct DaySource: TodaySource {
    var today = TodayFacts()
    var days: [Int: TodayFacts] = [:]
    func facts(now: Date) async -> TodayFacts { today }
    func facts(on day: Date, now: Date) async -> TodayFacts { days[paris.component(.day, from: day)] ?? TodayFacts(events: [], reminders: []) }
}

private func run(_ tool: GetTodayTool, _ arguments: ToolArguments) async throws -> String {
    let output = try await tool.execute(arguments, in: ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: monday))
    #expect(await tool.verify(arguments, output: output) == nil)
    guard case .string(let reply)? = output.values["reply"] else { return "" }
    return reply
}

@Suite struct AgendaDaysTests {
    private let tuesday = TodayFacts(events: [event("Point produit", 6, 10, 11), event("Revue", 6, 14, 15)],
                                     reminders: [ReminderItem(id: "r", title: "Appeler le dentiste", due: at(6, 9), hasTime: true)])

    @Test func tomorrow() async throws {
        let tool = GetTodayTool(source: DaySource(days: [6: tuesday]), calendar: paris)
        let reply = try await run(tool, ["date": .string("2026-10-06")])
        #expect(reply == "Demain, deux rendez-vous, le premier c'est Point produit à 10:00, et un rappel pour demain : Appeler le dentiste.")
    }

    @Test func aWeekdayNamesItsDate() async throws {
        let thursday = TodayFacts(events: [event("Réunion client", 8, 14, 15)], reminders: [])
        let tool = GetTodayTool(source: DaySource(days: [8: thursday]), calendar: paris)
        let reply = try await run(tool, ["date": .string("2026-10-08")])
        #expect(reply == "Jeudi 8 octobre, un rendez-vous : Réunion client à 14:00, et aucun rappel pour jeudi 8 octobre.")
    }

    @Test func tooFarOrPastIsRefusedBeforeAnything() async {
        let tool = GetTodayTool(source: DaySource(), calendar: paris)
        #expect(throws: ToolError.self) { try tool.day(["date": .string("2026-10-20")], now: monday) }
        #expect(throws: ToolError.self) { try tool.day(["date": .string("2026-10-04")], now: monday) }
        #expect(throws: ToolError.self) { try tool.day(["date": .string("jeudi")], now: monday) }
        #expect((try? tool.day(["date": .string("2026-10-19")], now: monday)) == paris.startOfDay(for: at(19, 0)))
        do { _ = try tool.day(["date": .string("2026-10-20")], now: monday) } catch {
            #expect(error.reason == "je ne regarde pas plus loin que quatorze jours")
        }
    }

    @Test func freeTimeBetweenEightAndEight() async throws {
        let tool = GetTodayTool(source: DaySource(days: [6: tuesday]), calendar: paris)
        let reply = try await run(tool, ["date": .string("2026-10-06"), "free_time": .bool(true)])
        // 8-10, 11-14, 15-20: 2 h + 3 h + 5 h.
        #expect(reply.hasSuffix("Du temps libre entre 8 h et 20 h : 10 h, le plus long créneau de 15 h à 20 h."))
    }

    @Test func freeTimeTodayStartsNowAndCountsTheMeetingInProgress() {
        let running = event("Stand-up", 5, 8, 10)
        let slots = FreeTime.slots(events: [running, event("Déjeuner", 5, 12, 13), event("Férié", 5, 0, 23, allDay: true)],
                                   day: monday, now: monday, calendar: paris)
        #expect(slots == [FreeTime.Slot(start: at(5, 10), end: at(5, 12)), FreeTime.Slot(start: at(5, 13), end: at(5, 20))])
        #expect(FreeTime.duration(6.5 * 3600) == "6 h 30")
        #expect(FreeTime.duration(45 * 60) == "45 min")
    }

    @Test func aFullDayHasNoFreeTime() {
        let busy = [event("Atelier", 6, 7, 21)]
        #expect(TodayPhrase.free(busy, day: at(6, 0), now: monday, calendar: paris) == "plus de temps libre entre 8 h et 20 h")
    }

    @Test func todayStillWorksWithoutArguments() async throws {
        let tool = GetTodayTool(source: DaySource(today: TodayFacts(events: [], reminders: nil)), calendar: paris)
        #expect(try await run(tool, [:]) == "Plus aucun rendez-vous aujourd'hui.")
    }
}

@MainActor
@Suite struct AgendaNeverToTheChatTests {
    @Test func agendaQuestionsAreRecognised() {
        for message in ["Qu'est-ce que j'ai demain ?", "qu’est-ce que j’ai jeudi", "J'ai quoi ce soir ?", "Combien de temps libre j'ai demain pour Yumi ?",
                        "Mes rendez-vous de lundi", "Est-ce que je suis libre jeudi à 14 h ?", "montre-moi mon agenda", "Quels sont mes rappels ?"] {
            #expect(ChatRoute.isPersonalAgenda(message), "\(message)")
        }
        for message in ["Explique-moi ce qu'est un Agent Runtime", "Crée-moi todo.md", "C'est quoi un calendrier grégorien ?", "Salut Yumi"] {
            #expect(!ChatRoute.isPersonalAgenda(message), "\(message)")
        }
    }

    @Test func whateverThePlannerSaysItNeverGoesToTheChat() {
        let message = "Combien de temps libre j'ai demain ?"
        #expect(ChatRoute.route(.failure(.cannotPlan("no calendar tool")), message: message) == .agendaKeptFromChat(.cannotPlan("no calendar tool")))
        #expect(ChatRoute.route(.failure(.invalidPlan("bad")), message: message) == .agendaKeptFromChat(.invalidPlan("bad")))
        #expect(ChatRoute.route(.failure(.noProvider), message: message) == .agendaKeptFromChat(.noProvider))
        #expect(ChatRoute.route(.failure(.busy), message: message) == .agendaKeptFromChat(.busy))
        #expect(ChatRoute.route(nil, message: message) == .agendaKeptFromChat(nil))
        // A talk message still goes to the chat.
        #expect(ChatRoute.route(.failure(.cannotPlan("talk")), message: "Explique-moi un Agent Runtime") == .chat)
    }

    @Test func aPlanWithGetTodayRunsInTheRuntime() async throws {
        let json = #"{"goal": "Demain", "steps": [{"description": "Lire demain", "tool": "get_today", "arguments": {"date": "2026-10-06", "free_time": true}}]}"#
        var tools = ToolRegistry.standard
        try tools.register(GetTodayTool(source: DaySource(), calendar: paris))
        let agent = RuntimeAgent(planner: LLMAgentPlanner(provider: ScriptedLLMProvider(json: json)), tools: tools)
        let route = ChatRoute.route(await agent.plan(for: AgentRequest(userIntent: "Qu'est-ce que j'ai demain ?")), message: "Qu'est-ce que j'ai demain ?")
        guard case .agent(let plan) = route else { Issue.record("expected the runtime, got \(route)"); return }
        #expect(plan.requiredTools == ["get_today"])
        #expect(plan.steps.first?.requiresApproval == false)
    }

    @Test func whatYumiSaysNeverAsksToPasteData() {
        for error in [nil, AgentError.cannotPlan("x"), .invalidPlan("x"), .providerFailed("x")] {
            let text = AgentLook.agendaKeptFromChat(error)
            #expect(!text.lowercased().contains("copi") && !text.lowercased().contains("colle"), "\(text)")
            #expect(text.contains("qu'est-ce que j'ai demain"))
        }
        #expect(AgentLook.agendaKeptFromChat(.noProvider).contains("Claude Code"))
        let prompt = ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/d")
        #expect(prompt.contains("ne lui demande jamais de te copier ces données"))
        let planner = PlannerPrompt.make(for: AgentRequest(userIntent: "x"), tools: [], maxSteps: 12)
        #expect(planner.system.contains("answered with get_today and its date"))
    }
}
