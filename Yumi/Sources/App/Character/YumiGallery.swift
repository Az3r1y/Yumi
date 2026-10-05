#if DEBUG
import SwiftUI

// The character sheet of design/yumi/maquette/reference.html, rebuilt with the Swift engine:
// same sections, same order, same sizes, so the two can be compared side by side.
// Opened by `YUMI_DEMO=gallery` (see BotDemo). Debug builds only.

@MainActor
final class YumiGalleryModel {
    struct Cell: Identifiable {
        let id = UUID()
        let label: String
        let engine: BotEngine
        var pose: YumiPose? = nil
    }

    let habits: [Cell]
    let poses: [Cell]
    let moods: [Cell]
    let rims: [Cell]
    /// The scenes of Contracts/EventAnimations.swift
    let scenes: [(cell: Cell, scene: YumiScene)]
    private var rounds = 0

    init() {
        func cell(_ label: String, pose: YumiPose? = nil, _ setup: (BotEngine) -> Void) -> Cell {
            let engine = BotEngine()
            setup(engine)
            return Cell(label: label, engine: engine, pose: pose)
        }
        habits = zip(YumiHabit.allCases, ["Clope", "Épuisé", "Café", "Casque", "Lunettes", "Nuage", "Sifflote", "Dodo", "Matcha"])
            .map { habit, label in cell(label) { $0.setHabit(habit) } }
        // `POSES` of the mock-up, each with the face it wears on the sheet
        let sheet: [(YumiPose, String, YumiMood)] = [
            (.jump, "Saut", .neutral), (.stretch, "Étirer", .surprised), (.squash, "S'écraser", .worried),
            (.shake, "Secouer", .annoyed), (.celebrate, "Célébrer", .happy),
            (.wave, "Salut", .happy), (.boing, "Boing", .neutral), (.arrive, "Arrive", .neutral),
        ]
        poses = sheet.map { pose, label, mood in cell(label, pose: pose) { $0.setMood(mood) } }
        moods = zip(YumiMood.allCases, ["Neutre", "Heureux", "Curieux", "Concentré", "Réfléchi", "Surpris", "Inquiet", "Agacé", "Clin d'œil", "Sommeil"])
            .map { mood, label in cell(label) { $0.setMood(mood) } }
        // `RIML` of the mock-up
        let tones: [(YumiRimTone, String, YumiMood)] = [
            (.calm, "Au repos", .neutral), (.work, "Au travail", .focused), (.think, "Réfléchit", .thinking),
            (.warn, "Attend ta réponse", .surprised), (.error, "Erreur", .worried), (.done, "Terminé", .happy), (.joy, "Content", .wink),
        ]
        rims = tones.map { tone, label, mood in cell(label) { $0.setMood(mood); $0.setRim(tone) } }
        let names: [(YumiScene, String)] = [
            (.star, "Étoile"), (.fork, "Fork"), (.pullRequest, "Pull request"), (.merge, "Fusion"), (.push, "Push"),
            (.commit, "Commit"), (.issue, "Issue"), (.release, "Release"), (.follower, "Abonné"),
        ]
        scenes = names.map { scene, label in (cell(label) { _ in }, scene) }
    }

    /// Plays the nine scenes; every other time as if three events had come at once.
    func playScenes() {
        rounds += 1
        for item in scenes { item.cell.engine.playScene(item.scene, count: rounds % 2 == 0 ? 3 : 1) }
    }

    func playPoses() {
        for cell in poses { if let pose = cell.pose { cell.engine.play(pose) } }
    }
}

struct YumiGalleryView: View {
    let model: YumiGalleryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Habitudes", model.habits, top: 30)
            row("Poses de la planche", model.poses, top: 30)
            row("Expressions", model.moods, top: 14)
            row("La lumière de contour porte l'état", model.rims, top: 14)
            row("Scènes (un événement, puis trois d'un coup)", model.scenes.map(\.cell), top: 34)
        }
        .padding(18)
        .frame(width: 980, height: 850, alignment: .topLeading)
        .background(Color(white: 0.06))
    }

    private func row(_ title: String, _ cells: [YumiGalleryModel.Cell], top: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.gray)
            HStack(spacing: 8) {
                ForEach(cells) { cell in
                    VStack(spacing: 6) {
                        // 72 units wide in the mock-up: a frame of 88 pt gives the same scale
                        YumiStage(engine: cell.engine, followsPointer: false)
                            .frame(width: 88, height: 74)
                        Text(cell.label).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.gray)
                    }
                    .padding(.top, top).padding(.bottom, 8).padding(.horizontal, 2)
                    .frame(width: 96)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black))
                }
            }
        }
    }
}
#endif
