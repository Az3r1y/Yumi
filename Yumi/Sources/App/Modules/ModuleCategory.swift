import Foundation

/// The three tabs of the open island: where a module lives. A module says its own category
/// (`YumiModule.category`); one that says nothing goes where its identifier puts it, and an
/// unknown module goes to "Journée", so a future module always has a place.
enum ModuleCategory: String, CaseIterable, Sendable {
    case work, day, relax

    /// "Travail", "Journée", "Détente".
    var label: String {
        switch self {
        case .work:  return loc("Travail")
        case .day:   return loc("Journée")
        case .relax: return loc("Détente")
        }
    }

    /// The category of a module from its identifier alone.
    static func of(moduleID id: String) -> ModuleCategory {
        switch id {
        case "claude-code", "github", "notion", "tasks", "taches": return .work
        case "agenda", "weather", "meteo", "notes", "gmail", "screen-time": return .day
        case "music", "musique", "focus":                          return .relax
        default:                                                   return .day
        }
    }

    /// The identifiers of one category, in the order given (the person's order).
    static func ids(_ ids: [String], in category: ModuleCategory,
                    category of: (String) -> ModuleCategory = { ModuleCategory.of(moduleID: $0) }) -> [String] {
        ids.filter { of($0) == category }
    }

    /// The categories that hold at least one of these modules, in tab order.
    static func present(in ids: [String],
                        category of: (String) -> ModuleCategory = { ModuleCategory.of(moduleID: $0) }) -> [ModuleCategory] {
        let found = Set(ids.map(of))
        return allCases.filter { found.contains($0) }
    }
}
