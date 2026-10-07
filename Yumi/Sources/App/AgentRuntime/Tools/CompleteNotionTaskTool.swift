import Foundation

/// A task of a chosen Notion database, as the completion needs it.
struct NotionTaskInfo: Equatable, Sendable {
    var title: String
    var base: String
    var baseID: String
    var done: Bool
}

/// The tasks the island lists, readable from any thread: the only ones that can be ticked.
final class NotionListedTasks: @unchecked Sendable {
    static let shared = NotionListedTasks()
    private let lock = NSLock()
    private var tasks: [String: NotionTaskInfo] = [:]

    func set(_ list: [NotionTask]) {
        let map = Dictionary(list.map { ($0.id, NotionTaskInfo(title: $0.title, base: $0.base, baseID: $0.baseID, done: false)) },
                             uniquingKeysWith: { a, _ in a })
        lock.withLock { tasks = map }
    }

    func info(page id: String) -> NotionTaskInfo? {
        lock.withLock { tasks.first { NotionAPI.sameID($0.key, id) }?.value }
    }
}

/// What `CompleteNotionTaskTool` needs from Notion. Implemented by `NotionAgentStore`.
protocol NotionCompletionStore: Sendable {
    /// The page, when it belongs to a chosen database. Throws `ToolError` with the reason in words.
    func task(page id: String) async throws -> NotionTaskInfo
    /// Ticks it done. Throws `ToolError` with the reason in words.
    func markDone(page id: String) async throws
}

/// Marks one task of a chosen Notion database as done: its checkbox, or its status. Asked from
/// the island when a task is ticked. Never changes anything else of the page.
struct CompleteNotionTaskTool: Tool {
    static let id = "complete_notion_task"

    var store: any NotionCompletionStore
    /// The page's title and database, known by the caller for the approval (the island lists them).
    var known: @Sendable (String) -> NotionTaskInfo? = { NotionListedTasks.shared.info(page: $0) }

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: Self.id,
            name: "Complete a Notion task",
            description: "Marks one task of a chosen Notion database as done, by its page id; only a task listed today or late; changes nothing else.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "page", type: .string, required: true, description: "the Notion page id of the task"),
            ]),
            risk: .write,
            outputKeys: ["reply"])
    }

    /// The database is the resource, an outside account: high, and asked each time.
    func action(for arguments: ToolArguments) -> ToolAction? {
        guard let page = page(arguments), let info = known(page) else { return nil }
        return ToolAction(kind: .modify, resources: [ResourceRef(.account, "notion:\(info.baseID)")], reversible: true,
                          content: loc("marquer « \(info.title) » comme terminée, dans la base Notion \(info.base)"))
    }

    func check(_ arguments: ToolArguments) async -> String? {
        guard let page = page(arguments) else { return loc("il me faut l'identifiant d'une page Notion") }
        guard known(page) != nil else { return loc("cette tâche n'est pas dans les bases Notion choisies") }
        do {
            let info = try await store.task(page: page)
            return info.done ? loc("« \(info.title) » est déjà terminée") : nil
        } catch {
            return (error as? ToolError)?.reason ?? loc("Notion ne répond pas")
        }
    }

    /// The plan the island runs when a task is ticked: one step, through the same approval.
    static func plan(for task: NotionTask) -> (AgentPlan, AgentRequest) {
        let intent = loc("Cocher « \(task.title) » dans Notion")
        let step = AgentStep(id: "step-1", description: intent, toolID: id, arguments: ["page": .string(task.id)], requiresApproval: true)
        return (AgentPlan(goal: intent, steps: [step], estimatedRisk: .write, requiredTools: [id], plannedBy: "island"),
                AgentRequest(userIntent: intent))
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        guard let page = page(arguments) else { throw ToolError.invalidInput(loc("il me faut l'identifiant d'une page Notion")) }
        try Task.checkCancellation()
        try await store.markDone(page: page)
        let title = known(page)?.title ?? ""
        return ToolOutput(summary: "Marked a Notion task done.",
                          values: ["reply": .string(loc("C'est coché dans Notion : \(title)."))])
    }

    /// Notion says the page is done now.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard let page = page(arguments) else { return loc("aucune page à vérifier") }
        guard let info = try? await store.task(page: page) else { return loc("je n'arrive pas à relire la tâche dans Notion") }
        return info.done ? nil : loc("Notion ne la montre pas comme terminée")
    }

    private func page(_ arguments: ToolArguments) -> String? {
        guard case .string(let raw)? = arguments["page"], let id = raw.nonEmptyTrimmed, NotionAPI.isPageID(id) else { return nil }
        return id
    }
}
