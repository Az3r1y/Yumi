import Foundation

// MARK: - Notion, through its public API
// Only what the module and the agent need: the databases shared with the person's internal
// integration, the tasks of the databases they chose, a new task, a page read back. Pure HTTP,
// with an injectable transport: no view, no state, no Keychain here.

/// A database the person chose, and which of its properties mean what.
struct NotionBase: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var titleProperty: String
    /// A date property: the day (and time) the task is due.
    var dateProperty: String?
    /// A checkbox, or a status whose value `doneValue` means done.
    var doneProperty: String?
    var doneIsCheckbox: Bool = true
    var doneValue: String?
}

/// One task read from a chosen database. Its title is data, never an instruction.
struct NotionTask: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var url: URL?
    var base: String
    /// The id of its database, to mark it done.
    var baseID: String = ""
    /// Its status or select value when it has one ("À faire", "En cours"), for the line's detail.
    var status: String? = nil
}

/// A page of a chosen database, any database: the latest edited ones show in the island, so a
/// base of clients or of documents is useful too, not only a base of tasks.
struct NotionPage: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var edited: Date
    var url: URL?
    var base: String
}

/// A database shared with the integration, and its properties by type, for the settings.
struct NotionDatabase: Equatable, Sendable {
    let id: String
    var name: String
    /// Property name → Notion type ("title", "date", "checkbox", "status"…).
    var properties: [String: String]
    /// Status property name → its options.
    var statusOptions: [String: [String]] = [:]

    var titleProperty: String? { properties.first { $0.value == "title" }?.key }
    func names(ofType type: String) -> [String] { properties.filter { $0.value == type }.map(\.key).sorted() }
}

enum NotionError: Error, Equatable, Sendable {
    /// No key saved.
    case noKey
    /// 401: the key is wrong or was revoked.
    case keyRefused
    /// 404 or 403: the database or the page is not shared with the integration.
    case notShared
    /// 429: wait this many seconds.
    case rateLimited(seconds: Int)
    case network
    case unexpected(Int)

    /// In words for the person.
    var reason: String {
        switch self {
        case .noKey: loc("il n'y a pas de clé Notion dans les réglages")
        case .keyRefused: loc("Notion refuse la clé, vérifie-la dans les réglages")
        case .notShared: loc("cette base n'est pas partagée avec ton intégration Notion")
        case .rateLimited(let seconds): loc("Notion demande d'attendre \(seconds) secondes")
        case .network: loc("Notion ne répond pas")
        case .unexpected(let status): loc("Notion a répondu par une erreur (\(status))")
        }
    }
}

struct NotionAPI: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let base = URL(string: "https://api.notion.com/v1/")!
    /// The dated version the requests are written for. Notion keeps older versions supported.
    static let version = "2022-06-28"

    var key: @Sendable () -> String?
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    var calendar: Calendar = .current

    // MARK: Requests

    /// The databases shared with the integration.
    func databases() async throws(NotionError) -> [NotionDatabase] {
        let body: [String: Any] = ["filter": ["property": "object", "value": "database"], "page_size": 100]
        let object = try await send("search", method: "POST", body: body)
        return (object["results"] as? [[String: Any]] ?? []).compactMap(Self.database(from:))
    }

    func database(id: String) async throws(NotionError) -> NotionDatabase {
        let object = try await send("databases/\(id)", method: "GET", body: nil)
        guard let database = Self.database(from: object) else { throw .unexpected(200) }
        return database
    }

    /// Unfinished tasks due on or before the end of `day` (`overdue` true), or on that day only.
    func tasks(in base: NotionBase, on day: Date, overdue: Bool) async throws(NotionError) -> [NotionTask] {
        let start = calendar.startOfDay(for: day)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try await tasks(in: base, from: overdue ? nil : start, before: next)
    }

    /// Unfinished tasks of the `days` days after `day`, today left out: what comes this week.
    func upcoming(in base: NotionBase, after day: Date, days: Int = 7) async throws(NotionError) -> [NotionTask] {
        let start = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: 1, to: start),
              let end = calendar.date(byAdding: .day, value: days + 1, to: start) else { return [] }
        return try await tasks(in: base, from: from, before: end)
    }

    /// The pages of the database edited last, whatever their properties.
    func recentPages(in base: NotionBase, limit: Int = 5) async throws(NotionError) -> [NotionPage] {
        let body: [String: Any] = ["sorts": [["timestamp": "last_edited_time", "direction": "descending"]], "page_size": limit]
        let object = try await send("databases/\(base.id)/query", method: "POST", body: body)
        return (object["results"] as? [[String: Any]] ?? []).compactMap { Self.page(from: $0, base: base) }
    }

    /// Unfinished tasks due from `from` (nil: any day before) to before `before`.
    private func tasks(in base: NotionBase, from: Date?, before: Date) async throws(NotionError) -> [NotionTask] {
        guard let dateProperty = base.dateProperty else { return [] }
        var filters: [[String: Any]] = [["property": dateProperty, "date": ["before": Self.dayString(before, calendar)]]]
        if let from { filters.append(["property": dateProperty, "date": ["on_or_after": Self.dayString(from, calendar)]]) }
        if let done = base.doneProperty {
            if base.doneIsCheckbox {
                filters.append(["property": done, "checkbox": ["equals": false]])
            } else if let value = base.doneValue {
                filters.append(["property": done, "status": ["does_not_equal": value]])
            }
        }
        let body: [String: Any] = ["filter": ["and": filters], "sorts": [["property": dateProperty, "direction": "ascending"]], "page_size": 50]
        let object = try await send("databases/\(base.id)/query", method: "POST", body: body)
        return (object["results"] as? [[String: Any]] ?? []).compactMap { Self.task(from: $0, base: base, calendar: calendar) }
    }

    /// Creates one page in the database: a title, and a day when given. Returns its id and link.
    func createTask(title: String, day: Date?, in base: NotionBase) async throws(NotionError) -> (id: String, url: URL?) {
        var properties: [String: Any] = [base.titleProperty: ["title": [["text": ["content": title]]]]]
        if let day, let dateProperty = base.dateProperty {
            properties[dateProperty] = ["date": ["start": Self.dayString(day, calendar)]]
        }
        let object = try await send("pages", method: "POST", body: ["parent": ["database_id": base.id], "properties": properties])
        guard let id = object["id"] as? String else { throw .unexpected(200) }
        return (id, (object["url"] as? String).flatMap(URL.init(string:)))
    }

    /// Marks a page of the database done: its checkbox ticked, or its status set to the done value.
    /// Only the done property is sent; nothing else of the page changes.
    func markDone(pageID: String, in base: NotionBase) async throws(NotionError) {
        guard Self.isPageID(pageID), let value = Self.doneValue(for: base) else { throw .unexpected(0) }
        _ = try await send("pages/\(pageID)", method: "PATCH", body: ["properties": [base.doneProperty!: value]])
    }

    /// The page as Notion has it now: its database, and whether it is done for this base.
    func pageState(id: String, base: NotionBase) async throws(NotionError) -> (database: String?, done: Bool, title: String?) {
        guard Self.isPageID(id) else { throw .notShared }
        let object = try await send("pages/\(id)", method: "GET", body: nil)
        let parent = (object["parent"] as? [String: Any])?["database_id"] as? String
        return (parent, Self.isDone(object, base: base), Self.title(of: object))
    }

    /// The value written to mark a task done. nil when the base has no done property.
    static func doneValue(for base: NotionBase) -> [String: Any]? {
        guard base.doneProperty != nil else { return nil }
        if base.doneIsCheckbox { return ["checkbox": true] }
        guard let value = base.doneValue else { return nil }
        return ["status": ["name": value]]
    }

    static func isDone(_ page: [String: Any], base: NotionBase) -> Bool {
        guard let done = base.doneProperty, let value = (page["properties"] as? [String: [String: Any]])?[done] else { return false }
        if base.doneIsCheckbox { return value["checkbox"] as? Bool == true }
        return ((value["status"] as? [String: Any])?["name"] as? String) == base.doneValue
    }

    /// A Notion id: 32 hexadecimal digits, with or without dashes. Nothing else reaches a path.
    static func isPageID(_ text: String) -> Bool {
        let digits = text.replacingOccurrences(of: "-", with: "")
        return digits.count == 32 && digits.allSatisfy(\.isHexDigit)
    }

    /// Two Notion ids are the same with or without their dashes.
    static func sameID(_ a: String, _ b: String) -> Bool {
        a.replacingOccurrences(of: "-", with: "").lowercased() == b.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// The title of a page, read back.
    func pageTitle(id: String) async throws(NotionError) -> String? {
        let object = try await send("pages/\(id)", method: "GET", body: nil)
        return Self.title(of: object)
    }

    private func send(_ path: String, method: String, body: [String: Any]?) async throws(NotionError) -> [String: Any] {
        guard let key = key()?.nonEmptyTrimmed else { throw .noKey }
        guard let url = URL(string: path, relativeTo: Self.base) else { throw .unexpected(0) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport(request) } catch { throw .network }
        let http = response as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200..<300:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .unexpected(200) }
            return object
        case 401: throw .keyRefused
        case 403, 404: throw .notShared
        case 429: throw .rateLimited(seconds: Int(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60)
        case let status: throw .unexpected(status)
        }
    }

    // MARK: Reading the answers

    static func database(from object: [String: Any]) -> NotionDatabase? {
        guard object["object"] as? String == "database", let id = object["id"] as? String else { return nil }
        let name = ((object["title"] as? [[String: Any]]) ?? []).compactMap { $0["plain_text"] as? String }.joined()
        var properties: [String: String] = [:]
        var options: [String: [String]] = [:]
        for (key, value) in object["properties"] as? [String: [String: Any]] ?? [:] {
            guard let type = value["type"] as? String else { continue }
            properties[key] = type
            if type == "status" {
                options[key] = ((value["status"] as? [String: Any])?["options"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            }
        }
        return NotionDatabase(id: id, name: name.isEmpty ? loc("Sans titre") : name, properties: properties, statusOptions: options)
    }

    static func task(from page: [String: Any], base: NotionBase, calendar: Calendar) -> NotionTask? {
        guard let id = page["id"] as? String else { return nil }
        let properties = page["properties"] as? [String: [String: Any]] ?? [:]
        var due: Date?
        var hasTime = false
        if let dateProperty = base.dateProperty, let start = (properties[dateProperty]?["date"] as? [String: Any])?["start"] as? String {
            (due, hasTime) = parseDate(start, calendar: calendar)
        }
        // A task already done is not a task to do, whatever the filter said.
        if let done = base.doneProperty, let value = properties[done] {
            if base.doneIsCheckbox, value["checkbox"] as? Bool == true { return nil }
            if !base.doneIsCheckbox, let name = (value["status"] as? [String: Any])?["name"] as? String, name == base.doneValue { return nil }
        }
        let title = Self.title(of: page) ?? loc("Sans titre")
        return NotionTask(id: id, title: title, due: due, hasTime: hasTime,
                          url: (page["url"] as? String).flatMap(URL.init(string:)), base: base.name, baseID: base.id,
                          status: status(of: properties, except: base.doneProperty))
    }

    static func page(from object: [String: Any], base: NotionBase) -> NotionPage? {
        guard let id = object["id"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let text = object["last_edited_time"] as? String ?? ""
        let edited = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? .distantPast
        return NotionPage(id: id, title: title(of: object) ?? loc("Sans titre"), edited: edited,
                          url: (object["url"] as? String).flatMap(URL.init(string:)), base: base.name)
    }

    /// The first status or select value of a page, the done property aside.
    static func status(of properties: [String: [String: Any]], except done: String?) -> String? {
        for key in properties.keys.sorted() where key != done {
            guard let value = properties[key], let type = value["type"] as? String, type == "status" || type == "select" else { continue }
            if let name = (value[type] as? [String: Any])?["name"] as? String, let clean = name.nonEmptyTrimmed { return clean }
        }
        return nil
    }

    static func title(of page: [String: Any]) -> String? {
        let properties = page["properties"] as? [String: [String: Any]] ?? [:]
        guard let title = properties.values.first(where: { $0["type"] as? String == "title" })?["title"] as? [[String: Any]] else { return nil }
        return title.compactMap { $0["plain_text"] as? String ?? (($0["text"] as? [String: Any])?["content"] as? String) }.joined().nonEmptyTrimmed
    }

    /// "2026-10-07" (a day) or "2026-10-07T14:00:00.000+02:00" (a moment).
    static func parseDate(_ text: String, calendar: Calendar) -> (Date?, Bool) {
        if text.count == 10 {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return (nil, false) }
            return (calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), false)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return (date, true) }
        formatter.formatOptions = [.withInternetDateTime]
        return (formatter.date(from: text), formatter.date(from: text) != nil)
    }

    static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The Notion app opens `notion://` links; the browser keeps the https one.
    static func appLink(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https" else { return url }
        return URL(string: "notion://" + url.absoluteString.dropFirst("https://".count))
    }
}
