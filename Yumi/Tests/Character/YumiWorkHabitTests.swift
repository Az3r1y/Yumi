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
        #expect(YumiWorkHabit.habit(for: .smoke, filming: false) == .smoke)
        #expect(YumiWorkHabit.habit(for: .coffee, filming: false) == .coffee)
        #expect(YumiWorkHabit.habit(for: .matcha, filming: false) == .matcha)
    }

    @Test func noCigaretteOnFilm() {
        #expect(YumiWorkHabit.habit(for: .smoke, filming: true) == .coffee)
        #expect(YumiWorkHabit.habit(for: .matcha, filming: true) == .matcha)
    }
}
