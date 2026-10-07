import Combine
import Foundation

/// The modules as the person arranges them: in the island first, then in the second square,
/// then hidden. The settings and the island's edit mode both read and change this one list;
/// the registry keeps the truth (`ModuleSelection`, saved under the same keys as before).
@MainActor
final class ModuleLineup: ObservableObject {
    static let shared = ModuleLineup()

    struct Entry: Identifiable, Equatable, Sendable {
        var id: String { snapshot.id }
        /// What names and draws the module: what it says right now is left out, so the list
        /// does not change at each tick of a timer.
        var snapshot: ModuleSnapshot
        var selected: Bool

        init(module: ModuleSnapshot, selected: Bool) {
            var plain = ModuleSnapshot(id: module.id, name: module.name, colorHex: module.colorHex, status: "",
                                       title: "", subtitle: "", primaryAction: "", secondaryAction: nil)
            plain.symbol = module.symbol
            snapshot = plain
            self.selected = selected
        }
    }

    /// Where a module goes, by its place among the selected ones.
    enum Place: Equatable, Sendable { case island, secondSquare, hidden }

    @Published private(set) var entries: [Entry] = []
    private var moveTo: (@MainActor (String, Int) -> [Entry])?
    private var selectTo: (@MainActor (String, Bool) -> [Entry])?

    init() {}

    func attach(entries: [Entry], move: @escaping @MainActor (String, Int) -> [Entry],
                select: @escaping @MainActor (String, Bool) -> [Entry]) {
        self.entries = entries
        moveTo = move
        selectTo = select
    }

    var selected: [Entry] { entries.filter(\.selected) }
    var hidden: [Entry] { entries.filter { !$0.selected } }

    static func place(of index: Int, selected: Bool) -> Place {
        guard selected else { return .hidden }
        return index < ModuleCatalog.pinnedLimit ? .island : .secondSquare
    }

    func place(of id: String) -> Place {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return .hidden }
        return Self.place(of: index, selected: true)
    }

    /// Puts a shown module at `index` among the shown ones.
    func move(_ id: String, to index: Int) {
        guard let moveTo else { return }
        entries = moveTo(id, index)
    }

    /// One step up or down, for the keyboard and the accessibility actions.
    func nudge(_ id: String, by step: Int) {
        guard let index = selected.firstIndex(where: { $0.id == id }) else { return }
        move(id, to: index + step)
    }

    func setShown(_ id: String, _ shown: Bool) {
        guard let selectTo else { return }
        entries = selectTo(id, shown)
    }

    /// The registry changed on its own (a module reported a new name, a new module arrived).
    func refresh(_ entries: [Entry]) {
        if entries != self.entries { self.entries = entries }
    }
}
