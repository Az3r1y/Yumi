import Foundation

/// What Yumi has in hand while an agent works, chosen in the settings: a cigarette, a coffee
/// or a matcha. The cigarette can be turned off (YUMI.md): it is one choice among three.
enum YumiWorkHabit: String, CaseIterable, Sendable {
    case smoke, coffee, matcha

    /// Where the choice is kept.
    static let defaultsKey = "workHabit"
    /// The old switch "Cigarette", on or off, kept to carry the person's choice over.
    static let oldSmokeKey = "habitSmoke"

    var habit: YumiHabit {
        switch self {
        case .smoke:  return .smoke
        case .coffee: return .coffee
        case .matcha: return .matcha
        }
    }

    var label: String {
        switch self {
        case .smoke:  return "Cigarette"
        case .coffee: return "Café"
        case .matcha: return "Matcha"
        }
    }

    /// The person's choice. Before the three choices there was a switch: on gives the
    /// cigarette, off the coffee. A new installation starts with the coffee.
    static func current(in defaults: UserDefaults = .standard) -> YumiWorkHabit {
        if let raw = defaults.string(forKey: defaultsKey), let choice = YumiWorkHabit(rawValue: raw) { return choice }
        if defaults.object(forKey: oldSmokeKey) != nil { return defaults.bool(forKey: oldSmokeKey) ? .smoke : .coffee }
        return .coffee
    }

    /// What he holds at work. On film there is no cigarette: the coffee takes its place.
    static func habit(for choice: YumiWorkHabit, filming: Bool) -> YumiHabit {
        filming && choice == .smoke ? .coffee : choice.habit
    }
}
