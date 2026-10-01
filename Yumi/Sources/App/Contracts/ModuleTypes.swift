import Foundation

// MARK: - Module contract
// A module is one thing Yumi watches: Claude Code, the calendar, a timer, the weather.
// The core fills `AppState.modules` with snapshots; the island draws them. Both sides
// rely on this file, so neither edits it during the parallel work (see YUMI.md).

/// What the island needs to draw one module, and nothing else.
struct ModuleSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    /// Shown in full in the island. No abbreviations.
    var name: String
    /// Hex colour, e.g. "#5B8CFF".
    var colorHex: String
    /// One or two words: "14:30", "2 sessions", "19°".
    var status: String
    /// Headline of the detail view: "Point produit dans 12 min".
    var title: String
    /// One line under the headline.
    var subtitle: String
    /// Label of the main button, and of the optional second one.
    var primaryAction: String
    var secondaryAction: String?
    /// True when the user should look now. The island may open by itself.
    var needsAttention: Bool = false
    /// What the folded island shows when this module has something going on right now.
    /// nil when nothing is happening. The folded island shows the live module with the
    /// highest priority; with none, it shows nothing on the right.
    var live: ModuleLive? = nil
    /// SF Symbol of this module in the island's rail and overview: "calendar", "music.note".
    var symbol: String = "circle.fill"
    /// SF Symbols of the main and second buttons where the island draws round buttons:
    /// "pause.fill", "forward.fill", "video.fill". nil lets the island pick a neutral arrow.
    var primarySymbol: String? = nil
    var secondarySymbol: String? = nil
    /// A bar the activity view can draw: a track playing, a timer running. nil without one.
    var progress: ModuleProgress? = nil
}

/// How far along something is, with the two labels at the ends of the bar.
struct ModuleProgress: Equatable, Sendable {
    /// 0 to 1.
    var fraction: Double
    /// Left label: "1:52".
    var leading: String
    /// Right label: "3:14".
    var trailing: String
}

/// Something happening now, small enough for the folded island.
struct ModuleLive: Equatable, Sendable {
    /// A few words: "Lueur · Halo Nord", "18:42", "14:30 Point produit".
    var text: String
    /// Higher wins. Use the values of `ModuleLivePriority`.
    var priority: Int
    /// Buttons the folded island shows on hover, two at most.
    var controls: [ModuleControl] = []
}

/// A button of the folded island. Pressing it posts `moduleAction` with `id` as the action.
struct ModuleControl: Identifiable, Equatable, Sendable {
    /// "primary" or "secondary", the same actions as the buttons of the detail view.
    let id: String
    /// SF Symbol name: "pause.fill", "play.fill", "forward.fill".
    var symbol: String
    /// Accessibility label: "Pause", "Suivant".
    var label: String
}

enum ModuleLivePriority {
    /// Good to know, nothing to do: the next event, the weather.
    static let ambient = 10
    /// Something running that the user started: music playing, a focus timer.
    static let activity = 50
    /// Someone is waiting for the user: an approval, a question.
    static let attention = 100
}

enum ModuleCatalog {
    /// Modules shown in the island itself; the others go in the second square.
    static let pinnedLimit = 5
    /// Modules the user can have selected at once.
    static let selectionLimit = 10

    /// Example data so the island can be built before the real modules exist.
    /// The core replaces `AppState.modules` with live snapshots.
    static let placeholders: [ModuleSnapshot] = [
        .init(id: "claude-code", name: "Claude Code", colorHex: "#FFB547", status: "2 sessions", title: "yumi : écrit les tests", subtitle: "2 sessions ouvertes, 1 attend ta réponse", primaryAction: "Voir", secondaryAction: "Ouvrir le terminal"),
        .init(id: "agenda", name: "Agenda", colorHex: "#5B8CFF", status: "14:30", title: "Point produit dans 12 min", subtitle: "14:30 à 15:00, en visio", primaryAction: "Rejoindre", secondaryAction: "Voir la journée",
              live: ModuleLive(text: "14:30 Point produit", priority: ModuleLivePriority.ambient)),
        .init(id: "notes", name: "Notes", colorHex: "#F2C744", status: "3", title: "Dernière note", subtitle: "Idée : mode nuit pour Yumi", primaryAction: "Nouvelle note", secondaryAction: "Tout voir"),
        .init(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: "18:42", title: "Focus en cours", subtitle: "Session 2 sur 4, reste 18 min 42", primaryAction: "Pause", secondaryAction: "Arrêter"),
        .init(id: "music", name: "Musique", colorHex: "#F58AD9", status: "lecture", title: "Lueur", subtitle: "Halo Nord, Premières heures", primaryAction: "Pause", secondaryAction: "Suivant",
              live: ModuleLive(text: "Lueur · Halo Nord", priority: ModuleLivePriority.activity, controls: [
                  ModuleControl(id: "primary", symbol: "pause.fill", label: "Pause"),
                  ModuleControl(id: "secondary", symbol: "forward.fill", label: "Suivant"),
              ])),
        .init(id: "weather", name: "Météo", colorHex: "#7FD0FF", status: "19°", title: "19° et des éclaircies", subtitle: "Pluie vers 18 h, prends une veste", primaryAction: "Détail", secondaryAction: nil),
    ]
}

extension Notification.Name {
    /// Posted by the island when a module button is pressed.
    /// userInfo: ["module": String (module id), "action": String ("primary" or "secondary")]
    static let moduleAction = AppIdentity.notification("moduleAction")
}
