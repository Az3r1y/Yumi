import Combine
import Foundation

// The person's contributions, as on their GitHub profile: the 52 last weeks, one square a day,
// the total of the year and the current streak. Read with GitHub's GraphQL API
// (viewer.contributionsCollection.contributionCalendar), with the token of the Keychain, at most
// every 30 minutes.

/// One day of the calendar.
struct ContributionDay: Equatable, Sendable, Identifiable {
    /// "2026-10-08", as GitHub gives it: the person's calendar day.
    var date: String
    var count: Int
    /// 0 (none) to 4 (the most), GitHub's own quartiles.
    var level: Int
    var id: String { date }
}

struct ContributionCalendar: Equatable, Sendable {
    var total: Int
    /// Columns of seven days, Sunday first, oldest week first. The last one may be shorter.
    var weeks: [[ContributionDay]]

    var days: [ContributionDay] { weeks.flatMap { $0 } }

    /// Days in a row with at least one contribution, up to today. A today still empty does not
    /// break the streak: the day is not over.
    func streak(today: String) -> Int {
        let past = days.filter { $0.date <= today }.sorted { $0.date < $1.date }
        var count = 0
        for (index, day) in past.enumerated().reversed() {
            if day.count > 0 { count += 1; continue }
            if index == past.count - 1 && day.date == today { continue }
            break
        }
        return count
    }
}

/// Why there is no calendar to show.
enum ContributionsProblem: Error, Equatable, Sendable {
    case noToken
    /// The token works but may not read the profile.
    case missingScope
    /// GitHub asks to wait until this moment.
    case rateLimited(until: Date)
    case unreachable
}

enum GitHubContributionsFeed {
    static let query = """
    query { viewer { contributionsCollection { contributionCalendar { totalContributions \
    weeks { contributionDays { date contributionCount contributionLevel } } } } } }
    """

    static let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]

    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        return request
    }

    /// The answer of GitHub, read: the calendar, or why there is none.
    static func read(status: Int, data: Data, headers: [String: String], now: Date = .now) -> Result<ContributionCalendar, ContributionsProblem> {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let errors = object?["errors"] as? [[String: Any]] ?? []
        let limited = headers["x-ratelimit-remaining"] == "0" || status == 429
            || errors.contains { ($0["type"] as? String) == "RATE_LIMITED" }
        if limited || (status == 403 && headers["retry-after"] != nil) {
            let reset = headers["x-ratelimit-reset"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
                ?? headers["retry-after"].flatMap(Double.init).map { now.addingTimeInterval($0) }
                ?? now.addingTimeInterval(3600)
            return .failure(.rateLimited(until: max(reset, now.addingTimeInterval(60))))
        }
        if status == 401 { return .failure(.missingScope) }
        if status == 403 || errors.contains(where: { ["INSUFFICIENT_SCOPES", "FORBIDDEN"].contains($0["type"] as? String ?? "") }) {
            return .failure(.missingScope)
        }
        guard status == 200,
              let calendar = (((object?["data"] as? [String: Any])?["viewer"] as? [String: Any])?["contributionsCollection"]
                as? [String: Any])?["contributionCalendar"] as? [String: Any],
              let weeks = calendar["weeks"] as? [[String: Any]] else {
            return .failure(errors.isEmpty ? .unreachable : .missingScope)
        }
        let columns = weeks.map { week in
            (week["contributionDays"] as? [[String: Any]] ?? []).compactMap { day -> ContributionDay? in
                guard let date = day["date"] as? String else { return nil }
                return ContributionDay(date: date, count: day["contributionCount"] as? Int ?? 0,
                                       level: levels[day["contributionLevel"] as? String ?? ""] ?? 0)
            }
        }
        return .success(ContributionCalendar(total: calendar["totalContributions"] as? Int ?? 0, weeks: columns))
    }

    /// "2026-10-08" for a date, in the person's calendar.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The contributions as the module last read them, for the island and the settings.
@MainActor
final class GitHubContributions: ObservableObject {
    static let shared = GitHubContributions()

    /// The calendar is asked at most this often.
    static let refreshEvery: TimeInterval = 30 * 60
    /// Shown in the island's GitHub view.
    static let inIslandKey = "githubContributionsInIsland"
    /// "yumi" (Yumi's violet) or "github" (GitHub's green).
    static let paletteKey = "githubContributionsPalette"

    @Published private(set) var calendar: ContributionCalendar?
    @Published private(set) var problem: ContributionsProblem?
    private(set) var asked: Date?

    init() {}

    /// True when it is time to ask again: never asked, older than 30 minutes, or after the
    /// moment GitHub said to wait until.
    func due(now: Date = .now) -> Bool {
        if case .rateLimited(let until)? = problem { return now >= until }
        guard let asked else { return true }
        return now.timeIntervalSince(asked) >= Self.refreshEvery
    }

    func record(_ result: Result<ContributionCalendar, ContributionsProblem>, at now: Date = .now) {
        asked = now
        switch result {
        case .success(let calendar):
            self.calendar = calendar
            problem = nil
        case .failure(let problem):
            self.problem = problem
            // A problem other than the network makes an old calendar wrong to show
            if problem != .unreachable { calendar = nil }
        }
    }

    func clear() {
        calendar = nil
        problem = .noToken
        asked = nil
    }

    /// The sentence that says why there is no grid.
    nonisolated static func explanation(_ problem: ContributionsProblem) -> String {
        switch problem {
        case .noToken:
            return loc("Donne-moi un jeton GitHub pour voir tes contributions.")
        case .missingScope:
            return loc("Ton jeton ne me laisse pas lire tes contributions. Un jeton classique a besoin de read:user ; un jeton fin, de l'accès en lecture à ton profil.")
        case .rateLimited(let until):
            return loc("GitHub me demande d'attendre. Je réessaie à \(FrenchText.clock(until)).")
        case .unreachable:
            return loc("Je n'arrive pas à joindre GitHub. Je réessaie dans un moment.")
        }
    }
}
