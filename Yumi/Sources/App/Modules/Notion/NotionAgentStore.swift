import Foundation

/// `NotionTaskStore` over the Notion API and the databases chosen in the settings.
struct NotionAgentStore: NotionTaskStore {
    var api: NotionAPI
    var bases: @Sendable () -> [NotionBase] = { NotionBases.load() }

    func baseNames() -> [String] { bases().map(\.name) }

    func baseID(named name: String) -> String? { base(named: name)?.id }

    private func base(named name: String) -> NotionBase? { bases().first { $0.name == name } }

    func problem(base name: String) async -> String? {
        guard let base = base(named: name) else { return loc("je ne connais pas cette base Notion") }
        do {
            _ = try await api.database(id: base.id)
            return nil
        } catch {
            return error.reason
        }
    }

    func create(title: String, day: Date?, base name: String) async throws -> String {
        guard let base = base(named: name) else { throw ToolError.invalidInput(loc("je ne connais pas cette base Notion")) }
        do {
            return try await api.createTask(title: title, day: day, in: base).id
        } catch {
            // Never tried again: a page may have been created before the error came back.
            throw ToolError.failed(error.reason)
        }
    }

    func title(ofPage id: String) async -> String? {
        try? await api.pageTitle(id: id)
    }
}

extension NotionAgentStore: NotionCompletionStore {
    /// The page, only when it belongs to one of the chosen databases.
    func task(page id: String) async throws -> NotionTaskInfo {
        let chosen = bases()
        guard let first = chosen.first else { throw ToolError.invalidInput(loc("aucune base Notion n'est choisie dans les réglages")) }
        var state: (database: String?, done: Bool, title: String?)
        do {
            state = try await api.pageState(id: id, base: first)
            guard let database = state.database, let owner = chosen.first(where: { NotionAPI.sameID($0.id, database) }) else {
                throw ToolError.invalidInput(loc("cette tâche n'est pas dans les bases Notion choisies"))
            }
            // Done is read with the properties of the page's own database.
            if owner.id != first.id { state = try await api.pageState(id: id, base: owner) }
            return NotionTaskInfo(title: state.title ?? loc("Sans titre"), base: owner.name, baseID: owner.id, done: state.done)
        } catch let error as NotionError {
            throw ToolError.failed(error.reason)
        }
    }

    func markDone(page id: String) async throws {
        let info = try await task(page: id)
        guard let base = bases().first(where: { $0.id == info.baseID }), NotionAPI.doneValue(for: base) != nil else {
            throw ToolError.invalidInput(loc("la base \(info.base) n'a pas de case « terminé » choisie dans les réglages"))
        }
        do {
            try await api.markDone(pageID: id, in: base)
        } catch {
            throw ToolError.failed(error.reason)
        }
    }
}
