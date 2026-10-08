import Foundation

/// Where a task typed in the quick field goes. Chosen in Réglages > Général.
enum QuickTaskDestination: String, CaseIterable, Sendable {
    /// The default list of the Reminders app, on this Mac: `add_reminder`, a medium approval.
    case reminders
    /// A Notion database: `add_notion_task`, a high approval, asked every time.
    case notion

    static let defaultsKey = "quickTaskDestination"
    /// The Notion database, by name, when several are chosen.
    static let notionBaseKey = "quickTaskNotionBase"

    static func stored(_ defaults: UserDefaults = .standard) -> QuickTaskDestination {
        defaults.string(forKey: defaultsKey).flatMap(QuickTaskDestination.init(rawValue:)) ?? .reminders
    }

    /// The database to write to: the one chosen when it still exists, the only one otherwise.
    /// nil when there are several and none is chosen, or none at all.
    static func notionBase(among names: [String], _ defaults: UserDefaults = .standard) -> String? {
        if let chosen = defaults.string(forKey: notionBaseKey), names.contains(chosen) { return chosen }
        return names.count == 1 ? names[0] : nil
    }

    var toolID: String {
        switch self {
        case .reminders: "add_reminder"
        case .notion: "add_notion_task"
        }
    }
}

/// The global shortcut that opens the quick field: ⌥ Espace unless the person changed it.
struct QuickTaskShortcut: Equatable, Sendable {
    /// `NSEvent.ModifierFlags` raw value: ⌘ 1<<20, ⌥ 1<<19, ⌃ 1<<18, ⇧ 1<<17.
    var flags: UInt
    var keyCode: UInt16

    static let option: UInt = 1 << 19
    static let standard = QuickTaskShortcut(flags: option, keyCode: 49)

    static let enabledKey = "quickTaskShortcutEnabled"
    static let flagsKey = "quickTaskShortcutFlags"
    static let codeKey = "quickTaskShortcutCode"

    static func stored(_ defaults: UserDefaults = .standard) -> QuickTaskShortcut? {
        guard defaults.object(forKey: enabledKey) as? Bool ?? true else { return nil }
        let flags = (defaults.object(forKey: flagsKey) as? Int).map(UInt.init) ?? standard.flags
        let code = (defaults.object(forKey: codeKey) as? Int).map(UInt16.init) ?? standard.keyCode
        let shortcut = QuickTaskShortcut(flags: flags, keyCode: code)
        return shortcut.isValid ? shortcut : standard
    }

    func store(_ defaults: UserDefaults = .standard) {
        defaults.set(Int(flags), forKey: Self.flagsKey)
        defaults.set(Int(keyCode), forKey: Self.codeKey)
    }

    /// A global shortcut needs at least one of ⌘ ⌥ ⌃: Shift alone would eat a capital letter.
    var isValid: Bool { flags & ((1 << 20) | (1 << 19) | (1 << 18)) != 0 }
}

/// The task typed in the quick field, as a one-step plan for the runtime: the same tool, the
/// same approval and the same check as when Yumi is asked in words. No model is involved.
enum QuickTask {
    static func plan(_ draft: QuickTaskDraft, to destination: QuickTaskDestination, base: String?) -> (AgentPlan, AgentRequest) {
        var arguments: ToolArguments = ["title": .string(draft.title)]
        if let date = draft.dateArgument { arguments["date"] = .string(date) }
        switch destination {
        case .reminders:
            if let time = draft.timeArgument { arguments["time"] = .string(time) }
        case .notion:
            // A Notion task takes a day; the time stays out rather than be lost silently in the title.
            if let base { arguments["base"] = .string(base) }
        }
        let intent = destination == .reminders ? loc("Ajouter « \(draft.title) » à Rappels") : loc("Ajouter « \(draft.title) » à Notion")
        let id = destination.toolID
        let step = AgentStep(id: "step-1", description: intent, toolID: id, arguments: arguments, requiresApproval: true)
        return (AgentPlan(goal: intent, steps: [step], estimatedRisk: .write, requiredTools: [id], plannedBy: "island"),
                AgentRequest(userIntent: intent))
    }
}

extension Notification.Name {
    /// Posted by the settings when the quick task shortcut changes or is turned on or off.
    static let quickTaskShortcutChanged = AppIdentity.notification("quickTaskShortcutChanged")
}
