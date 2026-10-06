import Foundation

/// What Yumi has in hand while an agent works: a cigarette, a coffee or a matcha, chosen at
/// the first launch, or one of the three at random, set in the settings. The cigarette can be
/// turned off (YUMI.md): it is one choice among others.
enum YumiWorkHabit: String, CaseIterable, Sendable {
    case smoke, coffee, matcha, random

    /// The three offered at the first launch; the settings add the random one.
    static let firstChoices: [YumiWorkHabit] = [.coffee, .smoke, .matcha]

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

    /// What he holds for one session of work. The random choice draws one of the three each
    /// time an agent starts working (`draw` gives a number in 0..<1). On film there is no
    /// cigarette: the coffee takes its place.
    func habit(filming: Bool, draw: () -> Double = { .random(in: 0..<1) }) -> YumiHabit {
        let held: YumiHabit
        switch self {
        case .smoke:  held = .smoke
        case .coffee: held = .coffee
        case .matcha: held = .matcha
        case .random:
            let three: [YumiHabit] = [.smoke, .coffee, .matcha]
            held = three[min(2, Int(draw() * 3))]
        }
        return filming && held == .smoke ? .coffee : held
    }
}
