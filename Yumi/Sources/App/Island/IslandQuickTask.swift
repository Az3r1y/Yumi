import SwiftUI
import EventKit

// The quick task (Réglages > Général, ⌥ Espace by default): a single field « Nouvelle tâche »,
// Enter adds it to the destination of the settings through the agent runtime (the same tool,
// approval and check as when Yumi is asked in words), and under it the day's list of that
// destination, each line with a circle to tick. Escape folds the island.

/// One line of the day's list.
struct QuickTaskItem: Identifiable, Equatable {
    let id: String
    var title: String
    /// "15:00", empty for a task of the whole day.
    var time: String
    var late: Bool
}

@MainActor
final class QuickTaskBoard: ObservableObject {
    static let shared = QuickTaskBoard()

    @Published private(set) var items: [QuickTaskItem] = []
    /// What happened to the last task typed, or why the list cannot be read.
    @Published private(set) var note: String?
    @Published private(set) var busy = false
    @Published private(set) var ticking: Set<String> = []

    private let reminders = EKEventStore()
    private var notionTasks: [NotionTask] = []
    var parser = QuickTaskParser()

    var destination: QuickTaskDestination { QuickTaskDestination.stored() }
    var notionBase: String? { QuickTaskDestination.notionBase(among: NotionBases.load().map(\.name)) }

    /// Where the task goes, in words, for the field's subtitle.
    var destinationLabel: String {
        switch destination {
        case .reminders: return loc("Dans Rappels")
        case .notion: return notionBase.map { loc("Dans Notion, \($0)") } ?? loc("Dans Notion")
        }
    }

    func opened() {
        note = nil
        Task { await reload() }
    }

    // MARK: Adding

    /// Adds the task. True when it was added: the field empties.
    func add(_ text: String) async -> Bool {
        let draft = parser.parse(text)
        guard !draft.title.isEmpty, !busy else { return false }
        let destination = destination
        if destination == .notion, notionBase == nil {
            note = NotionBases.load().isEmpty ? loc("Choisis une base Notion dans les réglages.") : loc("Choisis la base Notion dans Réglages > Général.")
            return false
        }
        guard let agent = AppState.shared.agent else { note = loc("Je ne suis pas encore prêt, réessaie dans un instant."); return false }
        busy = true
        note = nil
        let (plan, request) = QuickTask.plan(draft, to: destination, base: notionBase)
        let result = await agent.execute(plan, for: request)
        busy = false
        // The approval took the island: come back to the field.
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.quickTask)
        if result.status.succeeded {
            note = loc("Ajouté : \(draft.title)")
            await reload()
            return true
        }
        note = result.status == .cancelled ? loc("Pas ajouté.") : (result.error.map { FrenchText.sentenceStart($0.message) } ?? loc("Pas ajouté."))
        return false
    }

    // MARK: The day's list

    func reload() async {
        switch destination {
        case .reminders: await loadReminders()
        case .notion: await loadNotion()
        }
    }

    func tick(_ item: QuickTaskItem) {
        guard !ticking.contains(item.id) else { return }
        switch destination {
        case .reminders:
            // A click on the circle is the person's own act, as in the Notes module.
            guard let reminder = reminders.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
            reminder.isCompleted = true
            guard (try? reminders.save(reminder, commit: true)) != nil else { note = loc("Rappels n'a pas coché la tâche."); return }
            items.removeAll { $0.id == item.id }
        case .notion:
            // Notion leaves the Mac: through the runtime and its approval, like the module's box.
            guard let task = notionTasks.first(where: { $0.id == item.id }), let agent = AppState.shared.agent else { return }
            ticking.insert(item.id)
            Task {
                let (plan, request) = CompleteNotionTaskTool.plan(for: task)
                _ = await agent.execute(plan, for: request)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.quickTask)
                await reload()
                ticking.remove(item.id)
            }
        }
    }

    private func loadReminders() async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            items = []
            note = note ?? loc("Autorise Yumi à lire tes Rappels pour voir ceux du jour.")
            return
        }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        let predicate = reminders.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let found: [QuickTaskItem] = await withCheckedContinuation { continuation in
            // EventKit answers on its own queue: the closure must not be isolated to the main actor.
            reminders.fetchReminders(matching: predicate) { @Sendable list in
                let today = calendar.startOfDay(for: Date())
                let items = (list ?? []).compactMap { reminder -> (Date, QuickTaskItem)? in
                    guard let components = reminder.dueDateComponents, let due = calendar.date(from: components) else { return nil }
                    let time = components.hour == nil ? "" : FrenchText.clock(due)
                    return (due, QuickTaskItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? loc("Rappel"),
                                               time: time, late: due < today))
                }
                continuation.resume(returning: items.sorted { $0.0 < $1.0 }.map(\.1))
            }
        }
        items = found
    }

    private func loadNotion() async {
        guard let name = notionBase, let base = NotionBases.load().first(where: { $0.name == name }) else {
            items = []
            return
        }
        do {
            let tasks = NotionBoard.ordered(try await YumiCore.notionAPI.tasks(in: base, on: Date(), overdue: true))
            notionTasks = tasks
            // The box of a line runs `complete_notion_task`, which only ticks a task it was shown.
            NotionListedTasks.shared.add(tasks)
            let today = Calendar.current.startOfDay(for: Date())
            items = tasks.map { task in
                QuickTaskItem(id: task.id, title: task.title, time: task.hasTime ? (task.due.map { FrenchText.clock($0) } ?? "") : "",
                              late: (task.due ?? today) < today)
            }
        } catch {
            items = []
            note = FrenchText.sentenceStart(error.reason) + "."
        }
    }
}

struct QuickTaskActivity: View {
    @ObservedObject var board = QuickTaskBoard.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    private let listLimit: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Nouvelle tâche").foregroundStyle(IslandTheme.faint))
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .focused($focused)
                    .onSubmit(add)
                    .disabled(board.busy)
                RoundButton(style: .white, symbol: "arrow.up", label: loc("Ajouter"), small: true, action: add)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(0)

            ActSub(text: hint).riseIn(1)

            if board.items.isEmpty {
                ActSub(text: loc("Rien pour aujourd'hui.")).riseIn(2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(board.items) { item in line(item) }
                    }
                }
                .frame(maxHeight: listLimit)
                .fixedSize(horizontal: false, vertical: board.items.count <= 5)
                .riseIn(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focused = true
            board.opened()
        }
    }

    /// What was read in the text, where it goes, or what happened to the last task.
    private var hint: String {
        if let note = board.note, text.isEmpty { return note }
        let draft = board.parser.parse(text)
        guard draft.day != nil else { return board.destinationLabel }
        return "\(board.destinationLabel) · \(when(draft))"
    }

    private func when(_ draft: QuickTaskDraft) -> String {
        guard let date = draft.day.flatMap({ Calendar.current.date(from: $0) }) else { return "" }
        var text: String
        if Calendar.current.isDateInToday(date) {
            text = loc("aujourd'hui")
        } else if Calendar.current.isDateInTomorrow(date) {
            text = loc("demain")
        } else {
            text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))
        }
        if let time = draft.timeArgument, board.destination == .reminders { text += " " + loc("à \(time)") }
        return text
    }

    private func line(_ item: QuickTaskItem) -> some View {
        HStack(spacing: 0) {
            Button { board.tick(item) } label: {
                Image(systemName: board.ticking.contains(item.id) ? "circle.dotted" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.late ? IslandTheme.amber : IslandTheme.muted)
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc("Marquer comme terminée"))
            .accessibilityLabel(loc("Marquer « \(item.title) » comme terminée"))
            Text(item.title)
                .font(IslandTheme.text(12, .semibold))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !item.time.isEmpty {
                Text(item.time)
                    .font(IslandTheme.round(11, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.faint)
                    .padding(.trailing, 7)
            }
        }
        .frame(height: 24)
    }

    private func add() {
        let typed = text
        guard typed.nonEmptyTrimmed != nil else { return }
        Task {
            if await board.add(typed) { text = "" }
            focused = true
        }
    }
}
