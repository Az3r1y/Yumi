import Foundation

/// What Yumi has in hand while an agent works: a coffee, a tea, a matcha, water, a juice, a
/// book, a gamepad, a knitting, a cigarette, or nothing at all, chosen at the first launch, or
/// one of them at random, set in the settings. The cigarette is one choice among others (YUMI.md).
enum YumiWorkHabit: String, CaseIterable, Sendable {
    case smoke, coffee, matcha, random
    case tea, water, juice, book, gamepad, knitting, nothing

    /// Every real habit, in the order they are offered: the random one is not among them.
    static let habits: [YumiWorkHabit] = [.coffee, .tea, .matcha, .water, .juice, .book, .gamepad, .knitting, .smoke, .nothing]
    /// Offered at the first launch: all of them; the settings add the random one.
    static let firstChoices: [YumiWorkHabit] = habits
    /// In the settings: all of them, then the random one.
    static let settingsChoices: [YumiWorkHabit] = habits + [.random]

    /// Where the choice is kept.
    static let defaultsKey = "workHabit"
    /// The old switch "Cigarette", on or off, kept to carry the person's choice over.
    static let oldSmokeKey = "habitSmoke"


    var label: String {
        switch self {
        case .smoke:  return "Cigarette"
        case .coffee: return loc("Café")
        case .matcha: return "Matcha"
        case .random: return loc("Aléatoire")
        case .tea:      return loc("Thé")
        case .water:    return loc("Eau")
        case .juice:    return loc("Jus")
        case .book:     return loc("Livre")
        case .gamepad:  return loc("Manette")
        case .knitting: return loc("Tricot")
        case .nothing:  return loc("Rien")
        }
    }

    /// What he holds with this choice (the random one draws its own each time).
    var held: YumiHabit? {
        switch self {
        case .smoke:    return .smoke
        case .coffee:   return .coffee
        case .matcha:   return .matcha
        case .tea:      return .tea
        case .water:    return .water
        case .juice:    return .juice
        case .book:     return .book
        case .gamepad:  return .gamepad
        case .knitting: return .knitting
        case .nothing:  return .focus
        case .random:   return nil
        }
    }

    /// The person's choice. Before the choices there was a switch: on gives the cigarette,
    /// off the coffee. Until the person chooses, the coffee.
    static func current(in defaults: UserDefaults = .standard) -> YumiWorkHabit {
        if let raw = defaults.string(forKey: defaultsKey), let choice = YumiWorkHabit(rawValue: raw) { return choice }
        if defaults.object(forKey: oldSmokeKey) != nil { return defaults.bool(forKey: oldSmokeKey) ? .smoke : .coffee }
        return .coffee
    }

    /// True once the person has chosen (or had chosen with the old switch).
    static func isChosen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: defaultsKey).flatMap(YumiWorkHabit.init(rawValue:)) != nil
            || defaults.object(forKey: oldSmokeKey) != nil
    }

    /// What he holds for one session of work. The random choice draws one of all the habits
    /// each time an agent starts working (`draw` gives a number in 0..<1). On film there is no
    /// cigarette: the coffee takes its place.
    func habit(filming: Bool, draw: () -> Double = { .random(in: 0..<1) }) -> YumiHabit {
        let all = Self.habits.compactMap(\.held)
        let held = self.held ?? all[min(all.count - 1, Int(draw() * Double(all.count)))]
        return filming && held == .smoke ? .coffee : held
    }
}
