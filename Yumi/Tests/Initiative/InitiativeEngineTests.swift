import Testing
import Foundation

private var paris: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}
/// Thursday 1 October 2026 at the given time, Paris.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}
private func around(_ now: Date, talk: YumiTalk = .chatty, name: String? = "Esteban") -> Surroundings {
    Surroundings(now: now, calendar: paris, talk: talk, name: name)
}

/// One test per occasion: he says something fitting, in his voice.
@Suite struct InitiativeOccasionTests {
    private func say(_ occasion: Occasion, _ surroundings: Surroundings? = nil) -> YumiRemark? {
        var engine = InitiativeEngine()
        return engine.consider(occasion, in: surroundings ?? around(at(10)))
    }

    @Test func firstWakeOfTheDay() {
        let remark = say(.firstWake(events: 2, firstAt: at(10)), around(at(8)))
        #expect(remark?.text == "Salut Esteban. Deux rendez-vous aujourd'hui, le premier à 10 h.")
        #expect(remark?.action == nil)
        let one = say(.firstWake(events: 1, firstAt: at(14, 30)), around(at(8), name: nil))
        #expect(one?.text == "Salut. Un rendez-vous aujourd'hui, à 14 h 30.")
        #expect(say(.firstWake(events: 0, firstAt: nil), around(at(8)))?.text.hasPrefix("Salut Esteban.") == true)
    }

    @Test func backAfterALongAbsence() {
        let finished = say(.back(agentFinished: true, agentWaiting: false))
        #expect(finished?.text == "Te revoilà. Claude a fini pendant que tu étais parti.")
        #expect(finished?.action == "Voir")
        #expect(say(.back(agentFinished: true, agentWaiting: true))?.text == "Te revoilà. Claude attend ta réponse.")
        #expect(say(.back(agentFinished: false, agentWaiting: false))?.action == nil)
    }

    @Test func twoHoursWithoutABreak() {
        let remark = say(.longStretch(hours: 2))
        #expect(remark?.text == "Deux heures d'affilée. Une pause ?")
        #expect(remark?.action == "Pause")
    }

    @Test func aLongAgentTaskEnds() {
        let remark = say(.agentDone(project: "yumi", minutes: 18))
        #expect(remark?.text == "C'est passé, après dix-huit minutes. Bien joué.")
        #expect(remark?.action == "Voir")
        #expect(remark?.mood == .happy)
    }

    @Test func anAppointmentIsCloseWhileAnAgentWaits() {
        let remark = say(.meetingWhileAgentWaits(title: "Point produit", minutes: 10))
        #expect(remark?.text == "Point produit dans dix minutes, et Claude attend ta réponse.")
        #expect(remark?.action == "Voir")
    }

    @Test func itIsLate() {
        let remark = say(.late, around(at(23, 45)))
        #expect(remark?.text == "Il est tard. Je reste là, mais toi tu peux aller dormir.")
        #expect(remark?.mood == .asleep)
    }

    @Test func theBatteryIsLow() {
        #expect(say(.lowBattery(percent: 11))?.text == "Onze pour cent. Je dis ça, je dis rien.")
    }

    @Test func endOfTheWeek() {
        #expect(say(.weekEnd, around(at(18, 30, day: 2)))?.text == "Vendredi soir. Tu as bien bossé cette semaine.")
    }

    @Test func heUsesWhatHeKnowsWhenItFits() {
        var surroundings = around(at(8))
        surroundings.thread = ["Tu dois rendre une maquette de site à un client lundi."]
        surroundings.projects = ["Yumi : une app pour la notch"]
        let variants = InitiativePhrases.variants(for: .firstWake(events: 0, firstAt: nil), surroundings).map(\.text)
        #expect(variants.contains("Salut Esteban. Je n'ai pas oublié : tu dois rendre une maquette de site à un client lundi."))
        #expect(InitiativePhrases.variants(for: .back(agentFinished: false, agentWaiting: false), surroundings).map(\.text)
            .contains("Te revoilà. On reprend Yumi ?"))
        #expect(InitiativePhrases.variants(for: .weekEnd, surroundings).map(\.text).contains("Vendredi soir. Yumi attendra lundi."))
        #expect(InitiativePhrases.projectName("Tu avances sur plusieurs choses") == nil)
    }

    private var everyOccasion: [Occasion] {
        [.firstWake(events: 2, firstAt: at(10)), .firstWake(events: 0, firstAt: nil), .back(agentFinished: true, agentWaiting: false),
         .back(agentFinished: false, agentWaiting: true), .back(agentFinished: false, agentWaiting: false), .longStretch(hours: 3),
         .agentDone(project: "yumi", minutes: 42), .meetingWhileAgentWaits(title: "Point produit", minutes: 5), .late,
         .lowBattery(percent: 9), .weekEnd]
    }

    @Test func everySentenceIsInHisVoice() {
        var surroundings = around(at(10))
        surroundings.projects = ["Yumi : une app"]
        surroundings.thread = ["Tu voulais revoir la météo"]
        for occasion in everyOccasion {
            for named in [surroundings, around(at(10), name: nil)] {
                let variants = InitiativePhrases.variants(for: occasion, named)
                #expect(variants.count >= 3, "\(occasion)")
                #expect(Set(variants.map(\.key)).count == variants.count)
                for variant in variants {
                    let lower = " \(variant.text.lowercased()) "
                    for formula in VoiceTests.forbidden { #expect(!lower.contains(formula), "« \(variant.text) » contient « \(formula) »") }
                    #expect(VoiceTests.emoji(in: variant.text).isEmpty)
                    // One sentence, two at most, and short.
                    #expect(variant.text.count <= 110, "\(variant.text)")
                    #expect(variant.text.filter { ".?".contains($0) }.count <= 3, "\(variant.text)")
                    #expect(!variant.text.contains("  ") && !variant.text.contains(" ."), "\(variant.text)")
                }
            }
        }
    }
}

/// One test per rule that keeps him quiet.
@Suite struct InitiativeGuardTests {
    private let occasion = Occasion.agentDone(project: "yumi", minutes: 18)

    @Test func neverDuringAFocus() {
        var engine = InitiativeEngine()
        var surroundings = around(at(10))
        surroundings.focusRunning = true
        #expect(engine.refusal(of: occasion, in: surroundings) == .focus)
        #expect(engine.consider(occasion, in: surroundings) == nil)
        // Not even when someone waits.
        #expect(engine.refusal(of: .meetingWhileAgentWaits(title: "x", minutes: 5), in: surroundings) == .focus)
    }

    @Test func neverWhileTheScreenIsShared() {
        var surroundings = around(at(10))
        surroundings.screenShared = true
        #expect(InitiativeEngine().refusal(of: occasion, in: surroundings) == .screenShared)
    }

    @Test func neverDuringAPresentation() {
        var surroundings = around(at(10))
        surroundings.presenting = true
        #expect(InitiativeEngine().refusal(of: occasion, in: surroundings) == .presenting)
    }

    @Test func neverInDoNotDisturb() {
        var surroundings = around(at(10))
        surroundings.doNotDisturb = true
        #expect(InitiativeEngine().refusal(of: occasion, in: surroundings) == .doNotDisturb)
    }

    @Test func twentyMinutesBetweenTwoRemarks() {
        var engine = InitiativeEngine()
        let first = engine.consider(occasion, in: around(at(10)))
        #expect(first != nil)
        #expect(engine.refusal(of: .lowBattery(percent: 9), in: around(at(10, 19))) == .tooSoon)
        #expect(engine.refusal(of: .lowBattery(percent: 9), in: around(at(10, 20))) == nil)
    }

    @Test func unlessSomeoneIsWaitingForAnAnswer() {
        var engine = InitiativeEngine()
        _ = engine.consider(occasion, in: around(at(10)))
        let urgent = engine.consider(.meetingWhileAgentWaits(title: "Point produit", minutes: 8), in: around(at(10, 2)))
        #expect(urgent != nil)
    }

    @Test func ignoredSeveralTimesHeDropsTheSubjectForDays() {
        var engine = InitiativeEngine()
        for index in 0..<InitiativeEngine.ignoresBeforeSilence {
            let now = at(10, 0, day: 1 + index)
            let remark = engine.consider(.longStretch(hours: 2), in: around(now))
            #expect(remark != nil)
            engine.dismissed(id: remark!.id, ignored: true, now: now)
        }
        #expect(engine.refusal(of: .longStretch(hours: 2), in: around(at(10, 0, day: 4))) == .ignoredTooOften)
        #expect(engine.refusal(of: .longStretch(hours: 2), in: around(at(9, 0, day: 6))) == .ignoredTooOften)
        // Other subjects are not affected, and this one comes back after a few days.
        #expect(engine.refusal(of: .lowBattery(percent: 9), in: around(at(10, 0, day: 4))) == nil)
        #expect(engine.refusal(of: .longStretch(hours: 2), in: around(at(11, 0, day: 6))) == nil)
    }

    @Test func anAnswerOrAClosedRemarkIsNotBeingIgnored() {
        var engine = InitiativeEngine()
        for index in 0..<6 {
            let now = at(10, 0, day: 1 + index)
            let remark = engine.consider(.longStretch(hours: 2), in: around(now))!
            // Ignored twice, then answered: the count starts again.
            if index % 3 == 2 { _ = engine.accepted(id: remark.id) } else { engine.dismissed(id: remark.id, ignored: true, now: now) }
        }
        #expect(engine.refusal(of: .longStretch(hours: 2), in: around(at(10, 0, day: 7))) == nil)
        let remark = engine.consider(.longStretch(hours: 2), in: around(at(10, 0, day: 7)))!
        engine.dismissed(id: remark.id, ignored: false, now: at(10, 0, day: 7))
        #expect(engine.refusal(of: .longStretch(hours: 2), in: around(at(10, 0, day: 8))) == nil)
    }

    @Test func neverTheSameSentenceTwoDaysInARow() {
        var engine = InitiativeEngine()
        var texts: [String] = []
        for day in 1...6 {
            let remark = engine.consider(.late, in: around(at(23, 45, day: day)))
            #expect(remark != nil)
            texts.append(remark?.text ?? "")
        }
        for (yesterday, today) in zip(texts, texts.dropFirst()) { #expect(yesterday != today) }
        // And not twice the same day either.
        var sameDay = InitiativeEngine()
        let first = sameDay.consider(.lowBattery(percent: 12), in: around(at(9)))
        let second = sameDay.consider(.lowBattery(percent: 12), in: around(at(15)))
        #expect(first?.text != second?.text)
    }

    @Test func aFewTimesADayAtMostWhenDiscreet() {
        var engine = InitiativeEngine()
        var spoken = 0
        for hour in 8...20 where engine.consider(.agentDone(project: "yumi", minutes: 10 + hour), in: around(at(hour), talk: .discreet)) != nil {
            spoken += 1
        }
        #expect(spoken == InitiativeEngine.dailyLimit[.discreet])
        // The next day he may speak again, and someone waiting always gets through.
        #expect(engine.refusal(of: occasion, in: around(at(9, 0, day: 2), talk: .discreet)) == nil)
        #expect(engine.refusal(of: .meetingWhileAgentWaits(title: "x", minutes: 5), in: around(at(21), talk: .discreet)) == nil)
    }
}

@Suite struct InitiativeTalkTests {
    private let small: [Occasion] = [.firstWake(events: 0, firstAt: nil), .back(agentFinished: false, agentWaiting: false), .weekEnd]
    private let serious: [Occasion] = [.firstWake(events: 2, firstAt: at(10)), .back(agentFinished: true, agentWaiting: false),
                                       .back(agentFinished: false, agentWaiting: true), .longStretch(hours: 2),
                                       .agentDone(project: "yumi", minutes: 18), .meetingWhileAgentWaits(title: "x", minutes: 5),
                                       .late, .lowBattery(percent: 11)]

    @Test func silentSaysNothing() {
        for occasion in small + serious {
            #expect(InitiativeEngine().refusal(of: occasion, in: around(at(10), talk: .silent)) == .silent)
        }
    }

    @Test func discreetOnlySaysWhatMatters() {
        for occasion in serious { #expect(InitiativeEngine().refusal(of: occasion, in: around(at(10), talk: .discreet)) == nil, "\(occasion)") }
        for occasion in small { #expect(InitiativeEngine().refusal(of: occasion, in: around(at(10), talk: .discreet)) == .smallTalk, "\(occasion)") }
    }

    @Test func chattyAddsGreetingsAndEncouragements() {
        for occasion in small + serious { #expect(InitiativeEngine().refusal(of: occasion, in: around(at(10), talk: .chatty)) == nil, "\(occasion)") }
    }

    @Test func discreetIsTheDefault() {
        #expect(Surroundings(now: at(10)).talk == .discreet)
        #expect(YumiTalk(rawValue: "") == nil)
    }
}

@Suite struct InitiativeAnswerTests {
    @Test func theActionIsGivenOnceAndOnlyForTheRemarkOnScreen() {
        var engine = InitiativeEngine()
        let remark = engine.consider(.longStretch(hours: 2), in: around(at(10)))!
        #expect(engine.pendingID == remark.id)
        let wrong = engine.accepted(id: "someone-else")
        let action = engine.accepted(id: remark.id)
        let again = engine.accepted(id: remark.id)
        #expect(wrong == nil && action == .takeBreak && again == nil)
        let late = engine.dismissed(id: remark.id, ignored: true, now: at(10))
        #expect(!late)
    }

    @Test func whatHeSaidSurvivesARestart() throws {
        var engine = InitiativeEngine()
        _ = engine.consider(.late, in: around(at(23, 45)))
        let restored = try JSONDecoder().decode(InitiativeEngine.self, from: JSONEncoder().encode(engine))
        #expect(restored == engine)
        #expect(restored.refusal(of: .lowBattery(percent: 9), in: around(at(23, 50))) == .tooSoon)
    }
}
