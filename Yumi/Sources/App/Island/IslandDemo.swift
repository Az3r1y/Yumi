#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only. Launch with `YUMI_ISLAND_SHOTS=<folder>` to walk the island through
/// the launch and its eight views with example content, and save a PNG of the panel at each
/// step, to be compared with design/yumi/maquette/reference.html.
/// `YUMI_ISLAND_VIEW=<home|working|alert|finished|error|module|talk|drop|compact|folded-music>` instead
/// opens the island on one view and leaves it there.
@MainActor
enum IslandDemo {
    private static var started = false

    static func startIfRequested(controller: IslandWindowController) {
        let env = ProcessInfo.processInfo.environment
        guard !started, env["YUMI_ISLAND_SHOTS"] != nil || env["YUMI_ISLAND_VIEW"] != nil else { return }
        started = true
        // Nothing folds the island while it is being looked at
        controller.holdsOpen = true
        controller.fsm.homeToPetitDelay = 3600
        controller.fsm.petitToHiddenDelay = 3600
        Task { @MainActor in
            if let name = env["YUMI_ISLAND_VIEW"] {
                await pause(6.2)
                show(name, controller)
            } else {
                await walk(controller)
            }
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func walk(_ controller: IslandWindowController) async {
        // The launch: one picture every 250 ms
        for i in 0..<24 {
            await pause(0.25)
            shot(controller, String(format: "0-launch-%02d", i))
        }
        await pause(0.6)
        shot(controller, "1-compact")
        for name in ["home", "working", "alert", "finished", "error", "module", "music", "talk", "drop", "file", "drawer"] {
            show(name, controller)
            await pause(0.45); shot(controller, "2-\(name)-a")
            await pause(2.2);  shot(controller, "2-\(name)-b")
        }
        show("compact", controller)
        await pause(1.2); shot(controller, "3-compact-working")
        await walkFolded(controller)
        NSApp.terminate(nil)
    }

    /// The folded island with something live: the two examples of the contract (music and
    /// agenda), the buttons on hover, the next track sliding in, a title too long, then
    /// the agenda alone and nothing at all.
    private static func walkFolded(_ controller: IslandWindowController) async {
        for name in ["folded-music", "folded-hover", "folded-next", "folded-long", "folded-agenda", "folded-none"] {
            show(name, controller)
            await pause(0.12); shot(controller, "4-\(name)-a")
            await pause(0.2);  shot(controller, "4-\(name)-b")
            await pause(1.4);  shot(controller, "4-\(name)-c")
        }
        controller.demoHover = false
    }

    /// The examples of the contract, with another text for the music.
    private static func examples(music: String?, agenda: Bool = true) -> [ModuleSnapshot] {
        ModuleCatalog.placeholders.map { module in
            var module = module
            if module.id == "music" {
                if let music { module.live?.text = music } else { module.live = nil }
            }
            if module.id == "agenda", !agenda { module.live = nil }
            return module
        }
    }

    private static func show(_ name: String, _ controller: IslandWindowController) {
        let state = AppState.shared
        let model = IslandModel.shared
        state.pendingApproval = nil
        state.isPinned = false
        state.stateOverride = nil
        model.drawerOpen = false
        if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks[i].name = "yumi"
            state.tasks[i].steps = ["Lit · YUMI.md", "Modifie · IslandRootView.swift", "Écrit · IslandModel.swift",
                                    "Exécute · xcodebuild -scheme Yumi test"]
        }
        switch name {
        case "home":
            controller.expand(to: .overview)
        case "working":
            state.stateOverride = .working
            controller.expand(to: .overview)
        case "alert":
            state.stateOverride = .approval
            state.pendingApproval = ApprovalInfo(sessionId: "demo", tool: "Bash", command: "xcodebuild -scheme Yumi test")
            controller.expand(to: .approval)
        case "finished":
            state.stateOverride = .finished
            controller.expand(to: .finished)
        case "error":
            state.stateOverride = .error
            controller.expand(to: .error)
        case "module":
            model.selectedModuleID = "agenda"
            controller.expand(to: .module)
        case "music":
            model.selectedModuleID = "music"
            controller.expand(to: .module)
        case "talk":
            state.chatHistory = [
                ChatMessage(role: .user, content: "Résume-moi ce PDF en trois points"),
                ChatMessage(role: .assistant, content: "Budget validé à 42 k€, livraison le 14 novembre, un risque sur le prestataire vidéo."),
            ]
            controller.expand(to: .prompt)
        case "drop":
            state.droppedFile = nil
            controller.expand(to: .upload)
        case "file":
            state.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/Contrat-v3.pdf"), name: "Contrat-v3.pdf")
            controller.expand(to: .choose)
        case "drawer":
            controller.expand(to: .overview)
            model.drawerOpen = true
        case "folded-music":
            controller.demoHover = false
            state.modules = examples(music: "Lueur · Halo Nord")
            controller.collapse()
        case "folded-hover":
            controller.demoHover = true
        case "folded-next":
            state.modules = examples(music: "Marée basse · Halo Nord")
        case "folded-long":
            state.modules = examples(music: "Les heures lentes du petit matin sur la côte · Halo Nord et l'Orchestre des Marées")
        case "folded-agenda":
            controller.demoHover = false
            state.modules = examples(music: nil)
        case "folded-none":
            state.modules = examples(music: nil, agenda: false)
        default:
            state.stateOverride = .working
            controller.collapse()
        }
    }

    private static func shot(_ controller: IslandWindowController, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["YUMI_ISLAND_SHOTS"],
              let view = controller.window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
