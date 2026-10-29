import Foundation
import Testing

// yumi/pour-tous: Yumi without Claude Code, without a key and without Ollama. The simple mode,
// Apple's model when this Mac has it, and the automatic choice between them.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

/// Wednesday 14 October 2026, 10:00 in Paris.
private let wednesday = paris.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10))!
private let parser = SimpleRequestParser(calendar: paris, now: { wednesday })

private func reminder(_ text: String) -> QuickTaskDraft? {
    if case .reminder(let draft)? = parser.parse(text) { return draft }
    return nil
}

private func task(_ text: String) -> QuickTaskDraft? {
    if case .task(let draft)? = parser.parse(text) { return draft }
    return nil
}

private let allTools = ["add_reminder", "add_notion_task", "add_event", "start_focus", "get_current_time", "get_today", "control_music"]

@Suite struct SimpleRemindersTests {
    @Test func theExampleOfTheBrief() throws {
        let draft = try #require(reminder("rappelle-moi d'appeler maman demain 18 h"))
        #expect(draft.title == "Appeler maman")
        #expect(draft.dateArgument == "2026-10-15")
        #expect(draft.timeArgument == "18:00")
    }

    @Test func frenchForms() throws {
        let cases: [(String, String, String?, String?)] = [
            ("Rappelle-moi de sortir les poubelles ce soir 20h", "Sortir les poubelles", "2026-10-14", "20:00"),
            ("rappelle moi d'appeler Paul jeudi à 18h30", "Appeler Paul", "2026-10-15", "18:30"),
            ("Rappelle-moi d'acheter du pain à midi", "Acheter du pain", "2026-10-14", "12:00"),
            ("fais-moi penser à arroser les plantes vendredi", "Arroser les plantes", "2026-10-16", nil),
            ("rappelle-moi de payer le loyer le 3 novembre", "Payer le loyer", "2026-11-03", nil),
            ("Rappelle-moi de prendre mes médicaments à 9 h", "Prendre mes médicaments", "2026-10-15", "09:00"),
            ("rappelle-moi d'envoyer le devis après-demain 10 h 15", "Envoyer le devis", "2026-10-16", "10:15"),
            ("Ajoute un rappel : réserver le resto lundi 19 heures", "Réserver le resto", "2026-10-19", "19:00"),
            ("Yumi, rappelle-moi de rappeler Marie, s'il te plaît", "Rappeler Marie", nil, nil),
            ("rappelle-moi d'éteindre le four à 18h et demie", "Éteindre le four", "2026-10-14", "18:30"),
            ("rappelle-moi d'appeler le médecin à minuit", "Appeler le médecin", "2026-10-15", "00:00"),
        ]
        for (text, title, date, time) in cases {
            let draft = try #require(reminder(text), "\(text)")
            #expect(draft.title == title, "\(text)")
            #expect(draft.dateArgument == date, "\(text)")
            if let time { #expect(draft.timeArgument == time, "\(text)") }
        }
    }

    @Test func aTimeAloneAlreadyGoneIsForTomorrow() throws {
        let draft = try #require(reminder("rappelle-moi de prendre mes médicaments à 9 h"))
        #expect(draft.dateArgument == "2026-10-15")
        #expect(draft.timeArgument == "09:00")
    }

    @Test func englishForms() throws {
        let cases: [(String, String, String?, String?)] = [
            ("remind me to call mom tomorrow at 6pm", "Call mom", "2026-10-15", "18:00"),
            ("Remind me to water the plants on Friday", "Water the plants", "2026-10-16", nil),
            ("remind me to buy bread at noon", "Buy bread", "2026-10-14", "12:00"),
            ("Can you remind me to send the invoice tonight at 9:30 pm, please?", "Send the invoice", "2026-10-14", "21:30"),
            ("set a reminder to book the dentist next monday 10am", "Book the dentist", "2026-10-19", "10:00"),
            ("remind me to pay the rent on November 3", "Pay the rent", "2026-11-03", nil),
            ("remind me that Sam arrives tomorrow 3 pm", "Sam arrives", "2026-10-15", "15:00"),
        ]
        for (text, title, date, time) in cases {
            let draft = try #require(reminder(text), "\(text)")
            #expect(draft.title == title, "\(text)")
            #expect(draft.dateArgument == date, "\(text)")
            if let time { #expect(draft.timeArgument == time, "\(text)") }
        }
    }

    @Test func aReminderWithNothingToRememberIsNotOne() {
        #expect(reminder("rappelle-moi") == nil)
        #expect(reminder("remind me tomorrow") == nil || reminder("remind me tomorrow")?.title == "Tomorrow")
    }
}

@Suite struct SimpleTimesTests {
    @Test func spokenTimesBecomeTheFormsOfTheQuickParser() {
        #expect(SimpleRequestParser.timesNormalised("demain 18 h") == "demain 18h")
        #expect(SimpleRequestParser.timesNormalised("demain 18 h 30") == "demain 18h30")
        #expect(SimpleRequestParser.timesNormalised("demain 18h30") == "demain 18h30")
        #expect(SimpleRequestParser.timesNormalised("à 7 heures") == "à 7h")
        #expect(SimpleRequestParser.timesNormalised("à 7 heures 45") == "à 7h45")
        #expect(SimpleRequestParser.timesNormalised("à midi") == "à 12h")
        #expect(SimpleRequestParser.timesNormalised("à midi et demie") == "à 12h30")
        #expect(SimpleRequestParser.timesNormalised("à 9h et quart") == "à 9h15")
        #expect(SimpleRequestParser.timesNormalised("at 3 pm") == "at 3pm")
        #expect(SimpleRequestParser.timesNormalised("at 10:15 a.m.") == "at 10:15am")
        #expect(SimpleRequestParser.timesNormalised("at noon") == "at 12:00")
        #expect(SimpleRequestParser.timesNormalised("at 5 o'clock") == "at 5:00")
    }
}

@Suite struct SimpleTasksTests {
    @Test func theExampleOfTheBrief() throws {
        let draft = try #require(task("ajoute pain à mes tâches"))
        #expect(draft.title == "Pain")
        #expect(draft.dateArgument == nil)
    }

    @Test func forms() throws {
        let cases: [(String, String)] = [
            ("Ajoute lait et œufs à ma liste", "Lait et œufs"),
            ("mets les clés de Julie sur ma liste de courses", "Les clés de Julie"),
            ("rajoute « rendre le livre » à mes tâches", "« rendre le livre »"),
            ("Nouvelle tâche : appeler le plombier", "Appeler le plombier"),
            ("tâche finir le rapport", "Finir le rapport"),
            ("add bread to my to-do list", "Bread"),
            ("Add milk to my list", "Milk"),
            ("put batteries on the shopping list", "Batteries"),
            ("new task: renew passport", "Renew passport"),
            ("todo call the bank", "Call the bank"),
        ]
        for (text, title) in cases {
            let draft = try #require(task(text), "\(text)")
            #expect(draft.title == title, "\(text)")
        }
    }

    @Test func aTaskKeepsItsDay() throws {
        let draft = try #require(task("ajoute rendre le dossier vendredi à mes tâches"))
        #expect(draft.title == "Rendre le dossier")
        #expect(draft.dateArgument == "2026-10-16")
    }
}

@Suite struct SimpleEventsTests {
    @Test func theExampleOfTheBrief() {
        #expect(parser.parse("bloque jeudi 14 h réunion") == .event(title: "Réunion", date: "2026-10-15", time: "14:00", minutes: nil))
    }

    @Test func forms() {
        let cases: [(String, SimpleRequest)] = [
            ("Bloque demain 9h30 sport", .event(title: "Sport", date: "2026-10-15", time: "09:30", minutes: nil)),
            ("ajoute un rendez-vous dentiste mardi à 10 h", .event(title: "Dentiste", date: "2026-10-20", time: "10:00", minutes: nil)),
            ("rdv coiffeur vendredi 17h pendant 45 min", .event(title: "Coiffeur", date: "2026-10-16", time: "17:00", minutes: 45)),
            ("réserve lundi 14h pendant 2 h atelier", .event(title: "Atelier", date: "2026-10-19", time: "14:00", minutes: 120)),
            ("bloque jeudi 14h", .event(title: "Occupé", date: "2026-10-15", time: "14:00", minutes: nil)),
            ("schedule team lunch tomorrow at noon", .event(title: "Team lunch", date: "2026-10-15", time: "12:00", minutes: nil)),
            ("block friday 2pm for 30 minutes deep work", .event(title: "Deep work", date: "2026-10-16", time: "14:00", minutes: 30)),
            ("add a meeting with Ana on Monday at 11am", .event(title: "With Ana", date: "2026-10-19", time: "11:00", minutes: nil)),
        ]
        for (text, expected) in cases {
            #expect(parser.parse(text) == expected, "\(text)")
        }
    }

    @Test func anEventNeedsAStartTime() {
        #expect(parser.parse("bloque jeudi réunion") == nil)
    }
}

@Suite struct SimpleOtherRequestsTests {
    @Test func focus() {
        #expect(parser.parse("concentre-moi 25 min") == .focus(minutes: 25))
        #expect(parser.parse("Concentre-moi") == .focus(minutes: 25))
        #expect(parser.parse("lance un minuteur de 10 minutes") == .focus(minutes: 10))
        #expect(parser.parse("focus une heure") == .focus(minutes: 60))
        #expect(parser.parse("pomodoro") == .focus(minutes: 25))
        #expect(parser.parse("start a timer for 45 minutes") == .focus(minutes: 45))
        #expect(parser.parse("help me focus for half an hour") == .focus(minutes: 30))
        #expect(parser.parse("concentre-moi 2 min") == .focus(minutes: 5))
    }

    @Test func time() {
        for text in ["quelle heure est-il ?", "Il est quelle heure", "Quelle heure il est stp", "what time is it?", "What's the time"] {
            #expect(parser.parse(text) == .time, "\(text)")
        }
        #expect(parser.parse("à quelle heure est ma réunion demain ?") != .time)
    }

    @Test func theDay() {
        #expect(parser.parse("qu'est-ce que j'ai demain ?") == .day(date: "2026-10-15", freeTime: false))
        #expect(parser.parse("Qu'est-ce que j'ai aujourd'hui ?") == .day(date: "2026-10-14", freeTime: false))
        #expect(parser.parse("combien de temps libre j'ai jeudi ?") == .day(date: "2026-10-15", freeTime: true))
        #expect(parser.parse("ma journée") == .day(date: nil, freeTime: false))
        #expect(parser.parse("what do I have tomorrow?") == .day(date: "2026-10-15", freeTime: false))
        #expect(parser.parse("am I free on Friday?") == .day(date: "2026-10-16", freeTime: true))
    }

    @Test func music() {
        let cases: [(String, MusicCommand)] = [
            ("mets de la musique", .play), ("Lance la musique stp", .play), ("play some music", .play), ("musique", .play),
            ("pause", .pause), ("mets en pause", .pause), ("arrête la musique", .pause), ("stop the music", .pause),
            ("suivant", .next), ("chanson suivante", .next), ("passe ce morceau", .next), ("next", .next), ("skip this song", .next),
            ("précédent", .previous), ("morceau précédent", .previous), ("previous track", .previous),
        ]
        for (text, command) in cases {
            #expect(parser.parse(text) == .music(command), "\(text)")
        }
    }

    @Test func whatIsNotUnderstoodIsNotGuessed() {
        for text in ["", "   ", "bonjour", "raconte-moi une blague", "écris un poème sur la mer", "what is the capital of Peru?",
                     "supprime mes fichiers", "comment ça va ?"] {
            #expect(parser.parse(text) == nil, "\(text)")
        }
    }
}

@Suite struct SimplePlannerTests {
    private let planner = SimplePlanner(parser: parser, taskDestination: { (.reminders, nil) })

    @Test func aReminderBecomesAnApprovedWrite() throws {
        let proposal = planner.proposal(for: "rappelle-moi d'appeler maman demain 18 h", tools: allTools)
        #expect(proposal.engine == "simple")
        let step = try #require(proposal.steps?.first)
        #expect(step.tool == "add_reminder")
        #expect(step.arguments == ["title": .string("Appeler maman"), "date": .string("2026-10-15"), "time": .string("18:00")])

        // The same checks as a plan from a model: the registry and the policy decide.
        let registry = try ToolRegistry([AddReminderTool(store: FakeReminderStore())])
        let plan = try PlanValidator.validate(proposal, registry: registry, policy: AgentPolicy(maximumRisk: .write), plannedBy: "simple")
        #expect(plan.steps.allSatisfy { $0.requiresApproval })
        #expect(plan.plannedBy == "simple")
    }

    @Test func aTaskGoesWhereThePersonChose() throws {
        let reminders = planner.proposal(for: "ajoute pain à mes tâches", tools: allTools)
        #expect(reminders.steps?.first?.tool == "add_reminder")
        #expect(reminders.steps?.first?.arguments == ["title": .string("Pain")])

        let notion = SimplePlanner(parser: parser, taskDestination: { (.notion, "Courses") })
            .proposal(for: "ajoute pain à mes tâches", tools: allTools)
        #expect(notion.steps?.first?.tool == "add_notion_task")
        #expect(notion.steps?.first?.arguments == ["title": .string("Pain"), "base": .string("Courses")])
    }

    @Test func everyRequestHasItsTool() {
        let expected: [(String, String, ToolArguments)] = [
            ("bloque jeudi 14 h réunion", "add_event", ["title": .string("Réunion"), "date": .string("2026-10-15"), "time": .string("14:00")]),
            ("concentre-moi 25 min", "start_focus", ["minutes": .number(25)]),
            ("quelle heure est-il", "get_current_time", [:]),
            ("qu'est-ce que j'ai demain", "get_today", ["date": .string("2026-10-15")]),
            ("suivant", "control_music", ["action": .string("next")]),
        ]
        for (text, tool, arguments) in expected {
            let step = planner.proposal(for: text, tools: allTools).steps?.first
            #expect(step?.tool == tool, "\(text)")
            #expect(step?.arguments == arguments, "\(text)")
        }
    }

    @Test func withoutTheToolOrUnderstandingItDoesNotPlan() {
        let missing = planner.proposal(for: "mets de la musique", tools: ["add_reminder"])
        #expect(missing.steps == nil)
        #expect(missing.isAction == false)
        let unknown = planner.proposal(for: "écris un poème", tools: allTools)
        #expect(unknown.steps == nil)
        #expect(unknown.cannotPlan != nil)
        #expect(unknown.isAction == false)
    }

    @Test func aSimplePlanIsAlwaysRunByTheRuntime() throws {
        let registry = try ToolRegistry([GetCurrentTimeTool()])
        let proposal = planner.proposal(for: "quelle heure est-il", tools: ["get_current_time"])
        let plan = try PlanValidator.validate(proposal, registry: registry, policy: AgentPolicy(), plannedBy: "simple")
        #expect(ChatRoute.route(.success(plan)) == .agent(plan))
        // The same reading planned by a model stays with the conversation.
        let byModel = try PlanValidator.validate(proposal, registry: registry, policy: AgentPolicy(), plannedBy: "llm:engine:auto")
        #expect(ChatRoute.route(.success(byModel)) == .chat)
    }

    @Test func theReplyOffersButtonsAndAWayForward() {
        #expect(SimpleReply.suggestions.map(\.label).count == 5)
        #expect(SimpleReply.suggestions.contains { $0.sends })
        #expect(!SimpleReply.notUnderstood.localizedCaseInsensitiveContains("erreur"))
        #expect(SimpleReply.plugLater.contains("réglages"))
    }
}

@Suite struct EngineAgentPlannerTests {
    private let tools = [GetCurrentTimeTool().descriptor, AddReminderTool(store: FakeReminderStore()).descriptor]
    private func planner(_ provider: any LLMProvider, choice: Engine? = nil) -> EngineAgentPlanner {
        EngineAgentPlanner(llm: LLMAgentPlanner(provider: provider), simple: SimplePlanner(parser: parser),
                           choice: { choice })
    }

    @Test func withoutAnyModelTheSimpleModePlans() async throws {
        let proposal = try await planner(UnavailableLLMProvider()).propose(for: AgentRequest(userIntent: "rappelle-moi d'appeler maman demain 18 h"), tools: tools)
        #expect(proposal.engine == "simple")
        #expect(proposal.steps?.first?.tool == "add_reminder")
    }

    @Test func withoutAnyModelAnUnknownRequestGoesToTheConversation() async throws {
        let proposal = try await planner(UnavailableLLMProvider()).propose(for: AgentRequest(userIntent: "raconte-moi une histoire"), tools: tools)
        #expect(proposal.steps == nil)
        #expect(proposal.isAction == false)
    }

    @Test func aModelThatAnswersKeepsTheHand() async throws {
        let model = ScriptedLLMProvider(json: planJSON(goal: "L'heure", tools: ["get_current_time"]))
        let proposal = try await planner(model).propose(for: AgentRequest(userIntent: "rappelle-moi de partir"), tools: tools)
        #expect(proposal.goal == "L'heure")
        #expect(proposal.engine == nil)
    }

    @Test func whatAModelCouldNotPlanTheSimpleModeMayTake() async throws {
        let model = ScriptedLLMProvider(json: #"{"cannotPlan": "unclear", "isAction": false}"#)
        let proposal = try await planner(model).propose(for: AgentRequest(userIntent: "rappelle-moi de partir à 18h"), tools: tools)
        #expect(proposal.engine == "simple")
        let refused = ScriptedLLMProvider(json: #"{"cannotPlan": "deleting", "isAction": true}"#)
        let kept = try await planner(refused).propose(for: AgentRequest(userIntent: "rappelle-moi de partir à 18h"), tools: tools)
        #expect(kept.isAction == true)
    }

    @Test func aModelThatFailsFallsBackOnlyWhenTheSimpleModeUnderstands() async throws {
        let broken = ScriptedLLMProvider([.error(LLMProviderError.failed("offline"))])
        let proposal = try await planner(broken).propose(for: AgentRequest(userIntent: "quelle heure est-il"), tools: tools)
        #expect(proposal.engine == "simple")
        let broken2 = ScriptedLLMProvider([.error(LLMProviderError.failed("offline"))])
        await #expect(throws: AgentError.providerFailed(String(describing: LLMProviderError.failed("offline")))) {
            _ = try await planner(broken2).propose(for: AgentRequest(userIntent: "écris un poème"), tools: tools)
        }
    }

    @Test func theSimpleModeChosenNeverAsksAModel() async throws {
        let model = ScriptedLLMProvider(json: planJSON(tools: ["get_current_time"]))
        let proposal = try await planner(model, choice: .simple).propose(for: AgentRequest(userIntent: "quelle heure est-il"), tools: tools)
        #expect(proposal.engine == "simple")
        #expect(model.requests.isEmpty)
    }

    @Test func theEngineThatAnsweredIsRecorded() async throws {
        let provider = EngineLLMProvider(settings: { EngineSettings() }, make: { engine, _ in
            engine == .apple ? ScriptedLLMProvider(json: planJSON(tools: ["get_current_time"])) as any LLMProvider : UnavailableLLMProvider()
        })
        let proposal = try await LLMAgentPlanner(provider: provider).propose(for: AgentRequest(userIntent: "l'heure"), tools: tools)
        #expect(proposal.engine == "apple")
        #expect(Engine.named(proposal.engine) == .apple)
        #expect(Engine.named("engine:simple") == .simple)
    }
}

@Suite struct AutomaticEngineTests {
    @Test func whatThePersonSetUpComesFirstThenAppleThenSimple() {
        let settings = EngineSettings()
        #expect(settings.active { _ in false } == .simple)
        #expect(settings.active { $0 == .apple } == .apple)
        #expect(settings.active { $0 == .apple || $0 == .gemini } == .gemini)
        #expect(settings.active { $0 == .claudeCode || $0 == .apple } == .claudeCode)
    }

    @Test func aManualChoiceWins() {
        #expect(EngineSettings(choice: .simple).active { _ in true } == .simple)
        #expect(EngineSettings(choice: .apple).active { $0 == .apple } == .apple)
        // Chosen but not ready: the simple mode answers meanwhile.
        #expect(EngineSettings(choice: .apple).active { _ in false } == .simple)
    }

    @Test func theSimpleModeStaysLastWhateverTheSavedOrder() {
        #expect(EngineSettings.normalised([.simple, .apple]).last == .simple)
        #expect(EngineSettings.normalised([.simple, .apple]).first == .apple)
        #expect(EngineSettings(order: [.simple]).sequence.last == .simple)
    }

    @Test func appleAndSimpleAreReadyWithoutAnything() {
        let ready = EngineDetector.status(of: .simple, claudeCodeInstalled: false, hasKey: { _ in false }, ollamaModels: nil, ollamaModel: nil)
        #expect(ready.ready)
        let apple = EngineDetector.status(of: .apple, claudeCodeInstalled: false, hasKey: { _ in false }, ollamaModels: nil,
                                          ollamaModel: nil, apple: .available)
        #expect(apple.ready)
        let off = EngineDetector.status(of: .apple, claudeCodeInstalled: false, hasKey: { _ in false }, ollamaModels: nil,
                                        ollamaModel: nil, apple: .appleIntelligenceOff)
        #expect(!off.ready)
        #expect(Engine.apple.keychainKey == nil && Engine.simple.keychainKey == nil)
        #expect(Engine.apple.label == "Apple (sur ton Mac, gratuit)")
    }

    @Test func noProviderIsMadeForTheSimpleModeAndAppleNeverReachesTheNetwork() async {
        // On a Mac without the model, Apple says it is not there and the next engine is tried.
        if !AppleModelAvailability.current.isAvailable {
            await #expect(throws: LLMProviderError.unavailable) {
                _ = try await AppleLLMProvider().complete(LLMRequest(system: "", messages: [LLMMessage(role: .user, content: "Bonjour")],
                                                                    expectsJSON: false, maxOutputTokens: 20))
            }
        }
    }
}

@Suite struct AppleAvailabilityTests {
    @Test func everyUnavailableCaseSaysWhyAndWhatHappensMeanwhile() {
        let cases: [AppleModelAvailability] = [.systemTooOld, .deviceNotEligible, .appleIntelligenceOff, .modelDownloading, .languageNotSupported]
        for availability in cases {
            let message = availability.message ?? ""
            #expect(!message.isEmpty)
            #expect(message.contains("mode simple"), "\(availability)")
            #expect(!message.contains("—"))
            #expect(!availability.isAvailable)
            #expect(!availability.detail.isEmpty)
        }
        #expect(AppleModelAvailability.available.message == nil)
    }

    @Test func turningAppleIntelligenceOnGivesTheExactPath() {
        let message = AppleModelAvailability.appleIntelligenceOff.message ?? ""
        #expect(message.contains("Réglages Système"))
        #expect(message.contains("Apple Intelligence et Siri"))
        #expect(AppleModelAvailability.settingsURL.scheme == "x-apple.systempreferences")
        #expect(AppleModelAvailability.appleIntelligenceOff.canBecomeAvailable)
        #expect(AppleModelAvailability.modelDownloading.canBecomeAvailable)
        #expect(!AppleModelAvailability.deviceNotEligible.canBecomeAvailable)
    }

    @Test func theFirstLaunchNeverAsksAboutModels() {
        #expect(EngineWelcome.message(active: .apple, apple: .available)?.text == "Je tourne sur ton Mac, gratuitement, sans rien envoyer ailleurs.")
        let off = EngineWelcome.message(active: .simple, apple: .appleIntelligenceOff)
        #expect(off?.opensAppleSettings == true)
        #expect(off?.text.contains("Apple Intelligence") == true)
        let downloading = EngineWelcome.message(active: .simple, apple: .modelDownloading)
        #expect(downloading?.opensAppleSettings == false)
        #expect(downloading?.text.contains("téléchargement") == true)
        for apple in [AppleModelAvailability.systemTooOld, .deviceNotEligible, .languageNotSupported] {
            let simple = EngineWelcome.message(active: .simple, apple: apple)
            #expect(simple?.text.hasPrefix("Je comprends déjà les rappels") == true)
            #expect(simple?.opensAppleSettings == false)
        }
        #expect(EngineWelcome.message(active: .claudeCode, apple: .available) == nil)
    }

    @Test func guidedAnswersLoseTheirNulls() {
        let json = #"{"goal":"G","steps":[{"description":"d","tool":"add_reminder","arguments":{"title":"Pain","date":null}}],"cannotPlan":null}"#
        let proposal = try? PlannerPrompt.parse(AppleLLMProvider.withoutNulls(json))
        #expect(proposal?.steps?.first?.arguments == ["title": .string("Pain")])
        #expect(proposal?.cannotPlan == nil)
    }

    @Test func theConversationFitsTheSmallModel() {
        let messages = (1...10).map { LLMMessage(role: $0 % 2 == 1 ? .user : .assistant, content: "m\($0)") }
        let prompt = AppleLLMProvider.prompt(for: messages, keepingLast: 4)
        #expect(!prompt.contains("m6"))
        #expect(prompt.contains("Person: m7"))
        #expect(prompt.hasSuffix("Now:\nm10"))
        #expect(AppleLLMProvider.prompt(for: [LLMMessage(role: .user, content: "seul")]) == "seul")
    }
}

@Suite struct ControlMusicToolTests {
    private final class Player: MusicControl, @unchecked Sendable {
        let lock = NSLock()
        var commands: [MusicCommand] = []
        var problem: String?
        func perform(_ command: MusicCommand) async -> String? {
            lock.withLock { commands.append(command) }
            return problem
        }
    }

    private func context() -> ToolContext { ToolContext(runID: UUID(), stepID: "step-1", snapshot: nil, now: Date()) }

    @Test func itPlaysWithoutAskingAndSaysSo() async throws {
        let player = Player()
        let tool = ControlMusicTool(music: player)
        #expect(tool.riskLevel == .none)
        let output = try await tool.execute(["action": .string("next")], in: context())
        #expect(player.commands == [.next])
        #expect(output.values["reply"] == .string("Morceau suivant."))
    }

    @Test func anUnknownActionOrAProblemIsSaid() async {
        let tool = ControlMusicTool(music: Player())
        #expect(await tool.check(["action": .string("louder")]) != nil)
        let player = Player()
        player.problem = "rien ne joue en ce moment"
        await #expect(throws: ToolError.failed("rien ne joue en ce moment")) {
            _ = try await ControlMusicTool(music: player).execute(["action": .string("pause")], in: context())
        }
    }

    @Test func theTimeIsSaidInWords() async throws {
        let output = try await GetCurrentTimeTool(timeZone: paris.timeZone).execute([:], in: ToolContext(runID: UUID(), stepID: "s", snapshot: nil, now: wednesday))
        guard case .string(let reply)? = output.values["reply"] else { Issue.record("no reply"); return }
        #expect(reply.contains("10"))
    }
}
