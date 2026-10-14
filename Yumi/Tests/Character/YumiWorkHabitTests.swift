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
        d.set("cocoa", forKey: YumiWorkHabit.defaultsKey)
        #expect(YumiWorkHabit.current(in: d) == .coffee)
    }

    @Test func eachChoiceGivesItsHabit() {
        #expect(YumiWorkHabit.smoke.habit(filming: false) == .smoke)
        #expect(YumiWorkHabit.coffee.habit(filming: false) == .coffee)
        #expect(YumiWorkHabit.matcha.habit(filming: false) == .matcha)
    }

    @Test func randomDrawsAmongAllTheHabits() {
        let count = YumiWorkHabit.habits.count
        var drawn = Set<YumiHabit>()
        for i in 0..<count {
            drawn.insert(YumiWorkHabit.random.habit(filming: false, draw: { (Double(i) + 0.5) / Double(count) }))
        }
        #expect(drawn == Set(YumiWorkHabit.habits.compactMap(\.held)))
        #expect(drawn.count == count)
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0 }) == .coffee)
        #expect(YumiWorkHabit.random.habit(filming: false, draw: { 0.99999 }) == .focus)
    }

    @Test func everyChoiceHasALabelAndAHabit() {
        for choice in YumiWorkHabit.allCases {
            #expect(!choice.label.isEmpty)
            #expect(choice == .random || choice.held != nil)
        }
        #expect(Set(YumiWorkHabit.habits + [.random]) == Set(YumiWorkHabit.allCases))
        #expect(YumiWorkHabit.settingsChoices.last == .random)
        #expect(!YumiWorkHabit.firstChoices.contains(.random))
        #expect(Set(YumiWorkHabit.allCases.map(\.label)).count == YumiWorkHabit.allCases.count)
    }

    @Test func theNewChoicesAreReadBack() {
        for choice in [YumiWorkHabit.tea, .water, .juice, .book, .gamepad, .knitting, .nothing] {
            let d = defaults()
            d.set(choice.rawValue, forKey: YumiWorkHabit.defaultsKey)
            #expect(YumiWorkHabit.current(in: d) == choice)
        }
        #expect(YumiWorkHabit.nothing.habit(filming: false) == .focus)
        #expect(YumiWorkHabit.book.habit(filming: true) == .book)
    }

    @Test func noCigaretteOnFilm() {
        #expect(YumiWorkHabit.smoke.habit(filming: true) == .coffee)
        let smoke = YumiWorkHabit.habits.firstIndex(of: .smoke)!
        let draw = (Double(smoke) + 0.5) / Double(YumiWorkHabit.habits.count)
        #expect(YumiWorkHabit.random.habit(filming: true, draw: { draw }) == .coffee)
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
