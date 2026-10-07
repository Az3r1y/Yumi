import Testing
import Foundation

private let answer = """
{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"totalContributions":1204,"weeks":[
 {"contributionDays":[
  {"date":"2026-09-27","contributionCount":0,"contributionLevel":"NONE"},
  {"date":"2026-09-28","contributionCount":3,"contributionLevel":"FIRST_QUARTILE"},
  {"date":"2026-09-29","contributionCount":0,"contributionLevel":"NONE"},
  {"date":"2026-09-30","contributionCount":5,"contributionLevel":"SECOND_QUARTILE"},
  {"date":"2026-10-01","contributionCount":9,"contributionLevel":"THIRD_QUARTILE"},
  {"date":"2026-10-02","contributionCount":14,"contributionLevel":"FOURTH_QUARTILE"},
  {"date":"2026-10-03","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"}]},
 {"contributionDays":[
  {"date":"2026-10-04","contributionCount":2,"contributionLevel":"FIRST_QUARTILE"},
  {"date":"2026-10-05","contributionCount":0,"contributionLevel":"NONE"}]}
]}}}}}
"""

@Suite struct GitHubContributionsTests {
    private func read(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Result<ContributionCalendar, ContributionsProblem> {
        GitHubContributionsFeed.read(status: status, data: Data(body.utf8), headers: headers, now: Date(timeIntervalSince1970: 1_000))
    }

    @Test func theCalendarIsReadWeekByWeek() throws {
        let calendar = try read(answer).get()
        #expect(calendar.total == 1204)
        #expect(calendar.weeks.count == 2)
        #expect(calendar.weeks[0].count == 7 && calendar.weeks[1].count == 2)
        #expect(calendar.days.map(\.level) == [0, 1, 0, 2, 3, 4, 1, 1, 0])
        #expect(calendar.days[5].count == 14)
    }

    @Test func theStreakCountsDaysInARowAndForgivesAnEmptyToday() throws {
        let calendar = try read(answer).get()
        // 09-30 to 10-04: five days; 10-05 is today, still empty
        #expect(calendar.streak(today: "2026-10-05") == 5)
        #expect(calendar.streak(today: "2026-10-04") == 5)
        #expect(calendar.streak(today: "2026-10-06") == 0)
        #expect(calendar.streak(today: "2026-09-29") == 1)   // today empty, yesterday counted
    }

    @Test func aTokenWithoutTheRightIsSaid() {
        let scopes = #"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"Your token has not been granted the required scopes"}]}"#
        #expect(read(scopes) == .failure(.missingScope))
        #expect(read("{}", status: 401) == .failure(.missingScope))
        #expect(read(#"{"message":"Resource not accessible"}"#, status: 403) == .failure(.missingScope))
        #expect(GitHubContributions.explanation(.missingScope).contains("read:user"))
    }

    @Test func theRateLimitIsRespected() {
        let limited = read("{}", status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "4600"])
        #expect(limited == .failure(.rateLimited(until: Date(timeIntervalSince1970: 4600))))
        let graphql = read(#"{"errors":[{"type":"RATE_LIMITED"}]}"#)
        if case .failure(.rateLimited)? = Optional(graphql) {} else { Issue.record("expected rate limited") }
    }

    @MainActor @Test func theCalendarIsAskedAtMostEveryThirtyMinutes() {
        let store = GitHubContributions()
        let start = Date(timeIntervalSince1970: 10_000)
        #expect(store.due(now: start))
        store.record(read(answer), at: start)
        #expect(!store.due(now: start.addingTimeInterval(29 * 60)))
        #expect(store.due(now: start.addingTimeInterval(30 * 60)))
        store.record(.failure(.rateLimited(until: start.addingTimeInterval(3600))), at: start.addingTimeInterval(30 * 60))
        #expect(!store.due(now: start.addingTimeInterval(59 * 60)))
        #expect(store.due(now: start.addingTimeInterval(3600)))
        // The network failing keeps the last calendar; a refused token does not
        store.record(read(answer), at: start)
        store.record(.failure(.unreachable), at: start)
        #expect(store.calendar != nil)
        store.record(.failure(.missingScope), at: start)
        #expect(store.calendar == nil)
    }

    @Test func theRequestIsTheGraphQLQueryOfTheViewer() throws {
        let request = GitHubContributionsFeed.request(token: "t")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body?["query"]?.contains("contributionCalendar") == true)
    }
}
