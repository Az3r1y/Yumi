import Foundation

/// The Notion databases the person chose, as far as the agent needs them: add one page, read
/// its title back. The implementation lives with the Notion module (`NotionAgentStore`).
protocol NotionTaskStore: Sendable {
    /// The names of the chosen databases that have a title property.
    func baseNames() -> [String]
    /// Why a task cannot be added to this base right now (no key, not shared…), or nil.
    func problem(base: String) async -> String?
    /// Creates the page. Returns its id. Throws `ToolError` with the reason in words.
    func create(title: String, day: Date?, base: String) async throws -> String
    /// The title of the page, read back from Notion. nil when it cannot be found.
    func title(ofPage id: String) async -> String?
}

/// Adds one task (a page) to a Notion database the person chose: a title and, when given, a
/// day. Never changes, completes or removes an existing page.
struct AddNotionTaskTool: Tool {
    static let maxTitleLength = 200

    var store: any NotionTaskStore
    var calendar: Calendar = .current
    var now: @Sendable () -> Date = { Date() }

    var descriptor: ToolDescriptor {
        let bases = store.baseNames()
        return ToolDescriptor(
            id: "add_notion_task",
            name: "Add a Notion task",
            description: "Adds one task (a page) to a Notion database the person chose, with a day when they give one; never changes an existing page. Databases: \(bases.isEmpty ? "none set up" : bases.joined(separator: ", ")).",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "title", type: .string, required: true, description: "the task, as the person said it"),
                .init(name: "date", type: .string, required: false, description: "YYYY-MM-DD worked out from <now>; omit when no day is given"),
                .init(name: "base", type: .string, required: false, description: "the database name, required when there are several"),
            ]),
            risk: .write,
            outputKeys: ["id", "title", "reply"])
    }

    /// The approval shows the task, the day and the database.
    func action(for arguments: ToolArguments) -> ToolAction? {
        guard let title = title(arguments) else { return nil }
        var text = loc("la tâche « \(title) »")
        if let day = try? day(arguments, allowingPast: true) { text += ", " + loc("pour le \(NotionAPI.dayString(day, calendar))") }
        text += ", " + loc("dans la base Notion \((try? base(arguments)) ?? "?")")
        return ToolAction(kind: .create, resources: [ResourceRef(.unknown, text)], reversible: true)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        guard title(arguments) != nil else { return loc("il me faut un titre d'une ligne, de \(Self.maxTitleLength) caractères au plus") }
        do {
            _ = try day(arguments)
            return await store.problem(base: try base(arguments))
        } catch {
            return error.reason
        }
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        guard let title = title(arguments) else { throw ToolError.invalidInput(loc("il me faut un titre d'une ligne")) }
        let day = try day(arguments)
        let base = try base(arguments)
        try Task.checkCancellation()
        let id = try await store.create(title: title, day: day, base: base)
        return ToolOutput(summary: "Added the Notion task \(title).",
                          values: ["id": .string(id), "title": .string(title),
                                   "reply": .string(loc("C'est dans Notion, dans \(base) : \(title)."))])
    }

    /// The page exists, with this title.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let id)? = output.values["id"], let title = title(arguments) else { return loc("aucune page à vérifier") }
        guard let saved = await store.title(ofPage: id) else { return loc("la page « \(title) » n'est pas dans Notion") }
        return saved == title ? nil : loc("la page enregistrée s'appelle « \(saved) », pas « \(title) »")
    }

    // MARK: - Arguments

    private func title(_ arguments: ToolArguments) -> String? {
        guard case .string(let raw)? = arguments["title"] else { return nil }
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= Self.maxTitleLength, !title.contains(where: \.isNewline) else { return nil }
        return title
    }

    /// The database: the one named, or the only one.
    private func base(_ arguments: ToolArguments) throws(ToolError) -> String {
        let names = store.baseNames()
        guard !names.isEmpty else { throw .invalidInput(loc("aucune base Notion n'est choisie dans les réglages")) }
        if case .string(let raw)? = arguments["base"], let wanted = raw.nonEmptyTrimmed {
            guard let name = names.first(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) else {
                throw .invalidInput(loc("je ne connais pas la base « \(wanted) » ; les bases choisies : \(names.joined(separator: ", "))"))
            }
            return name
        }
        guard names.count == 1 else { throw .invalidInput(loc("dis-moi dans quelle base : \(names.joined(separator: ", "))")) }
        return names[0]
    }

    /// The day, nil when none was given. Never in the past.
    private func day(_ arguments: ToolArguments, allowingPast: Bool = false) throws(ToolError) -> Date? {
        guard case .string(let raw)? = arguments["date"], let text = raw.nonEmptyTrimmed else { return nil }
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day) else {
            throw .invalidInput(loc("« \(text) » n'est pas une date (AAAA-MM-JJ)"))
        }
        if !allowingPast, date < calendar.startOfDay(for: now()) { throw .invalidInput(loc("c'est un jour déjà passé")) }
        return date
    }
}
