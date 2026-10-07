import Foundation

/// `NotionTaskStore` over the Notion API and the databases chosen in the settings.
struct NotionAgentStore: NotionTaskStore {
    var api: NotionAPI
    var bases: @Sendable () -> [NotionBase] = { NotionBases.load() }

    func baseNames() -> [String] { bases().map(\.name) }

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
