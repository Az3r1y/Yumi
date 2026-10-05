import Foundation
import Testing

@Suite struct YumiWorkHabitTests {
    private func defaults() -> UserDefaults {
        let name = "yumi.tests.workhabit.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func newInstallationStartsWithCoffee() {
        #expect(YumiWorkHabit.current(in: defaults()) == .coffee)
    }

    @Test func cigaretteTurnedOnStaysCigarette() {
        let d = defaults()
        d.set(true, forKey: YumiWorkHabit.oldSmokeKey)
        #expect(YumiWorkHabit.current(in: d) == .smoke)
    }

    @Test func cigaretteTurnedOffBecomesCoffee() {
        let d = defaults()
        d.set(false, forKey: YumiWorkHabit.oldSmokeKey)
        #expect(YumiWorkHabit.current(in: d) == .coffee)
    }

    @Test func theNewChoiceWinsOverTheOldSwitch() {
        let d = defaults()
        d.set(true, forKey: YumiWorkHabit.oldSmokeKey)
        d.set("matcha", forKey: YumiWorkHabit.defaultsKey)
        #expect(YumiWorkHabit.current(in: d) == .matcha)
    }

    @Test func anUnknownValueFallsBack() {
        let d = defaults()
        d.set("tea", forKey: YumiWorkHabit.defaultsKey)
        #expect(YumiWorkHabit.current(in: d) == .coffee)
    }

    @Test func eachChoiceGivesItsHabit() {
        #expect(YumiWorkHabit.smoke.habit(filming: false) == .smoke)
        #expect(YumiWorkHabit.coffee.habit(filming: false) == .coffee)
        #expect(YumiWorkHabit.matcha.habit(filming: false) == .matcha)
    }

    @Test func randomDrawsOneOfTheThree() {
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0.1 }) == .smoke)
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0.5 }) == .coffee)
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0.9 }) == .matcha)
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0.99999 }) == .matcha)
    }

    @Test func noCigaretteOnFilm() {
        #expect(YumiWorkHabit.smoke.habit(filming: true) == .coffee)
        #expect(YumiWorkHabit.random.habit(filming: true, draw: { 0.1 }) == .coffee)
        #expect(YumiWorkHabit.matcha.habit(filming: true) == .matcha)
    }

    @Test func chosenOnlyOnceThePersonChose() {
        let d = defaults()
        #expect(!YumiWorkHabit.isChosen(in: d))
        d.set("random", forKey: YumiWorkHabit.defaultsKey)
        #expect(YumiWorkHabit.isChosen(in: d))
        #expect(YumiWorkHabit.current(in: d) == .random)
        let old = defaults()
        old.set(false, forKey: YumiWorkHabit.oldSmokeKey)
        #expect(YumiWorkHabit.isChosen(in: old))
    }
}
