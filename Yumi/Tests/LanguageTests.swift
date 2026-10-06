import Testing
import Foundation

// Yumi in French and in English: the catalog is complete, and the sentences the code writes,
// the dates and the requests read in both languages.

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 3) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func english<T>(_ body: () throws -> T) rethrows -> T {
    try AppLanguage.$forced.withValue("en", operation: body)
}

@Suite struct StringCatalogTests {
    private static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/App/Localization")

    private func strings(_ name: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent(name))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["strings"] as? [String: [String: Any]] ?? [:]
    }

    private func english(of entry: [String: Any]) -> String? {
        let localizations = entry["localizations"] as? [String: Any]
        let unit = (localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated" else { return nil }
        return unit?["value"] as? String
    }

    @Test func everyStringHasItsEnglish() throws {
        let catalog = try strings("Localizable.xcstrings")
        #expect(catalog.count > 700)
        let missing = catalog.filter { $0.value["extractionState"] as? String != "stale" && english(of: $0.value) == nil }.keys
        #expect(missing.isEmpty, "Without English: \(missing.sorted().prefix(20))")
    }

    @Test func everyTranslationKeepsItsPlaceholders() throws {
        let pattern = /%(?:\d+\$)?(@|lld|ld|d|f)/
        for (key, entry) in try strings("Localizable.xcstrings") {
            guard let value = english(of: entry) else { continue }
            let wanted = key.matches(of: pattern).map(\.output.1).sorted()
            let given = value.matches(of: pattern).map(\.output.1).sorted()
            #expect(wanted == given, "\(key) → \(value)")
        }
    }

    @Test func everyAccessRequestIsInEnglish() throws {
        let plist = try strings("InfoPlist.xcstrings")
        for key in ["NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription", "NSLocationWhenInUseUsageDescription",
                    "NSAppleEventsUsageDescription", "NSAccessibilityUsageDescription", "NSDownloadsFolderUsageDescription",
                    "NSDocumentsFolderUsageDescription", "NSDesktopFolderUsageDescription"] {
            #expect(plist[key].flatMap(english(of:)) != nil, "\(key)")
        }
    }
}

@Suite struct AppLanguageTests {
    @Test func theTestsSpeakFrenchUnlessTheyForceEnglish() {
        #expect(AppLanguage.current == "fr")
        #expect(loc("Réglages") == "Réglages")
        english {
            #expect(AppLanguage.current == "en")
            #expect(loc("Réglages") == "Settings")
        }
    }

    @Test func aLanguageIsReadFromItsCode() {
        #expect(AppLanguage.resolve("en-GB") == "en")
        #expect(AppLanguage.resolve("fr-CA") == "fr")
        #expect(AppLanguage.resolve("de") == "fr")
        #expect(AppLanguage.resolve(nil) == "fr")
    }

    @Test func aChoiceIsKeptForTheNextLaunch() {
        let defaults = UserDefaults(suiteName: "yumi.language.tests")!
        defaults.removePersistentDomain(forName: "yumi.language.tests")
        AppLanguage.choose(.english, defaults: defaults)
        #expect(AppLanguage.stored(defaults) == .english)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
        AppLanguage.choose(.automatic, defaults: defaults)
        #expect(defaults.persistentDomain(forName: "yumi.language.tests")?["AppleLanguages"] == nil)
    }
}

@Suite struct SentencesInBothLanguagesTests {
    private let point = AgendaEvent(id: "1", title: "Product sync", start: at(14, 30), end: at(15), isAllDay: false, location: "")

    @Test func theDayIsSaidInEnglish() {
        let facts = TodayFacts(events: [point], reminders: nil, weather: WeatherReport(temperature: 18.6, code: 3, hours: []))
        let french = TodayPhrase.reply(facts, now: at(9), calendar: paris)
        #expect(french == "Encore un rendez-vous aujourd'hui : Product sync à 14:30. Dehors, 19° et un ciel couvert.")
        english {
            let clock = FrenchText.clock(at(14, 30), calendar: paris)
            #expect(TodayPhrase.reply(facts, now: at(9), calendar: paris)
                    == "One more appointment today: Product sync at \(clock). Outside, 19° and overcast skies.")
        }
    }

    @Test func tomorrowIsTomorrow() {
        let tomorrow = AgendaEvent(id: "2", title: "Dentist", start: at(10, day: 4), end: at(11, day: 4), isAllDay: false, location: "")
        let facts = TodayFacts(events: [tomorrow], reminders: [], weather: nil)
        english {
            let reply = TodayPhrase.reply(facts, day: paris.startOfDay(for: at(10, day: 4)), now: at(9), freeTime: false, calendar: paris)
            #expect(reply.hasPrefix("Tomorrow, one appointment: Dentist at "))
            #expect(reply.contains("no reminders for tomorrow"))
        }
    }

    @Test func numbersAndDurationsAreSpelledInTheLanguage() {
        #expect(FrenchText.spelled(21, feminine: true) == "vingt et une")
        #expect(FrenchText.spokenMinutes(12 * 60) == "douze minutes")
        english {
            #expect(FrenchText.spelled(21) == "twenty-one")
            #expect(FrenchText.spokenMinutes(12 * 60) == "twelve minutes")
            #expect(FrenchText.spokenMinutes(65 * 60) == "one hour and five minutes")
        }
    }

    @Test func noFrenchHoursInEnglish() {
        #expect(FrenchText.spokenHour(at(18), calendar: paris) == "18 h")
        english {
            let hour = FrenchText.spokenHour(at(18), calendar: paris)
            #expect(!hour.contains(" h"))
            #expect(hour.contains("18") || hour.contains("6"))
            let earlier = RowTime.clock(at(9, day: 1), now: at(12), calendar: paris)
            #expect(earlier.contains("Oct") && earlier.contains("1"))
            #expect(RowTime.clock(at(9, day: 2), now: at(12), calendar: paris) == "yesterday")
        }
        #expect(RowTime.clock(at(9, day: 1), now: at(12), calendar: paris) == "1 oct.")
    }

    @Test func modulesSpeakEnglish() {
        english {
            let snapshot = ClaudeSessions.snapshot([])
            #expect(snapshot.title == "Nobody's coding right now.")
            #expect(snapshot.status == "idle")
            #expect(GitHubSummary.sentence(for: GitHubEvent(id: 1, kind: .fork, repo: "me/Yumi", actor: "lea")) == "lea forked Yumi.")
            #expect(Voice.goodbye(name: "Alex") == "See you later, Alex")
        }
    }

    @Test func aButtonKeepsItsSymbolInEnglish() {
        english {
            #expect(ModuleSymbols.button(loc("Rejoindre")) == "video.fill")
            #expect(ModuleSymbols.button(loc("Ouvrir le terminal")) == "terminal.fill")
        }
    }
}

@Suite struct EnglishRequestsTests {
    @Test func questionsAboutTheAgendaInEnglishStayAwayFromTheChat() {
        for message in ["What do I have tomorrow?", "what's on today", "Do I have any meetings on Thursday?",
                        "How much free time do I have on Friday?", "my appointments next week"] {
            #expect(ChatRoute.isPersonalAgenda(message), "\(message)")
        }
        for message in ["What's the capital of Peru?", "Tell me a joke", "remind me how a for loop works"] {
            #expect(!ChatRoute.isPersonalAgenda(message), "\(message)")
        }
    }

    @Test func thePlannerIsToldBothLanguagesAndToAnswerInThePersonsOne() {
        let request = AgentRequest(userIntent: "remind me to call the dentist at 10")
        let prompt = PlannerPrompt.make(for: request, tools: [], maxSteps: 4)
        #expect(prompt.system.contains("French or in English"))
        #expect(prompt.system.contains("in the language of <request>"))
    }

    @Test func theChatAnswersInTheLanguageOfTheMessage() {
        let prompt = ChatPhrases.systemPrompt(characterName: "Yumi", folder: "aucun")
        #expect(prompt.contains("dans la langue de son dernier message"))
    }
}
