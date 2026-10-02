import Foundation

/// The SF Symbols of the modules' round buttons. Each button label a module can show has its
/// symbol here, so a label and its drawing never disagree.
enum ModuleSymbols {
    private static let buttons: [String: String] = [
        "Voir": "eye.fill",
        "Relire": "eye.fill",
        "Brancher": "link",
        "Ouvrir le terminal": "terminal.fill",
        "Ouvrir l'éditeur": "curlybraces",
        "Ouvrir la session": "arrow.up.forward.app.fill",
        "Voir la journée": "calendar",
        "Rejoindre": "video.fill",
        "Ouvrir": "arrow.up.forward.app.fill",
        "Autoriser": "checkmark",
        "Ouvrir les réglages": "gearshape.fill",
        "Démarrer": "play.fill",
        "Lecture": "play.fill",
        "Reprendre": "play.fill",
        "Pause": "pause.fill",
        "Arrêter": "stop.fill",
        "Passer": "forward.fill",
        "Suivant": "forward.fill",
        "Recommencer": "arrow.counterclockwise",
        "Réessayer": "arrow.clockwise",
        "Fermer": "xmark",
        "Détail": "arrow.up.forward.app.fill",
        "Nouvelle note": "plus",
        "Terminé": "checkmark",
        "Activer les rappels": "bell.fill",
        "Tout voir": "list.bullet",
    ]

    /// The symbol of a button, from its label. "Ouvrir <an application>" opens that application.
    static func button(_ label: String?) -> String? {
        guard let label else { return nil }
        if let symbol = buttons[label] { return symbol }
        return label.hasPrefix("Ouvrir ") ? "arrow.up.forward.app.fill" : nil
    }
}

extension ModuleSnapshot {
    /// The snapshot with its module symbol and the symbols of its two buttons, taken from their labels.
    func withSymbols(_ module: String) -> ModuleSnapshot {
        var snapshot = self
        snapshot.symbol = module
        snapshot.primarySymbol = ModuleSymbols.button(primaryAction)
        snapshot.secondarySymbol = ModuleSymbols.button(secondaryAction)
        return snapshot
    }
}
