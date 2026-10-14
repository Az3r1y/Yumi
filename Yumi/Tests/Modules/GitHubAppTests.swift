import Testing
import Foundation

// Answers shaped like github.com's device flow and api.github.com's installations.

@Suite struct GitHubAppTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theDeviceCodeIsRead() throws {
        let data = Data(#"{"device_code":"3584d83530557fdd1f46af8289938c8ef79f9dc5","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8)
        let code = try #require(GitHubApp.deviceCode(from: data, now: now))
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(code.expires == now.addingTimeInterval(900))
        #expect(code.interval == 5)
    }

    @Test func aVerificationAddressElsewhereThanGitHubIsNotOpened() throws {
        let data = Data(#"{"device_code":"d","user_code":"AAAA-BBBB","verification_uri":"https://evil.example/login","interval":1}"#.utf8)
        let code = try #require(GitHubApp.deviceCode(from: data, now: now))
        #expect(code.verificationURL.host == "github.com")
        // Never faster than GitHub's minimum of five seconds.
        #expect(code.interval == 5)
    }

    @Test func aBrokenDeviceCodeAnswerGivesNothing() {
        #expect(GitHubApp.deviceCode(from: Data(#"{"error":"device_flow_disabled"}"#.utf8), now: now) == nil)
        #expect(GitHubApp.deviceCode(from: Data("<html>".utf8), now: now) == nil)
    }

    @Test func pollingAnswersAreRead() {
        #expect(GitHubApp.poll(from: Data(#"{"error":"authorization_pending"}"#.utf8), now: now) == .pending)
        #expect(GitHubApp.poll(from: Data(#"{"error":"slow_down","interval":10}"#.utf8), now: now) == .slowDown(10))
        #expect(GitHubApp.poll(from: Data(#"{"error":"expired_token"}"#.utf8), now: now) == .expired)
        #expect(GitHubApp.poll(from: Data(#"{"error":"access_denied"}"#.utf8), now: now) == .denied)
        #expect(GitHubApp.poll(from: Data(#"{"error":"bad_refresh_token"}"#.utf8), now: now) == .failed("bad_refresh_token"))
    }

    @Test func theTokenAndItsRefreshTokenAreRead() {
        let data = Data(#"{"access_token":"ghu_abc","expires_in":28800,"refresh_token":"ghr_def","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}"#.utf8)
        let expected = GitHubApp.Token(access: "ghu_abc", refresh: "ghr_def", expires: now.addingTimeInterval(28800),
                                       refreshExpires: now.addingTimeInterval(15_897_600))
        #expect(GitHubApp.poll(from: data, now: now) == .token(expected))
    }

    @Test func theTokenIsRenewedInItsLastMinutes() {
        let token = GitHubApp.Token(access: "ghu", refresh: "ghr", expires: now.addingTimeInterval(3600), refreshExpires: now.addingTimeInterval(86400))
        #expect(!token.needsRefresh(now: now))
        #expect(token.needsRefresh(now: now.addingTimeInterval(3600 - 60)))
        #expect(token.canRefresh(now: now.addingTimeInterval(3600)))
        #expect(token.usable(now: now.addingTimeInterval(4000)) == "ghu")
        // Both expired: sign in again.
        #expect(!token.canRefresh(now: now.addingTimeInterval(90000)))
        #expect(token.usable(now: now.addingTimeInterval(90000)) == nil)
    }

    @Test func aTokenThatNeverExpiresIsNeverRenewed() {
        let token = GitHubApp.Token(access: "ghu", refresh: nil, expires: nil, refreshExpires: nil)
        #expect(!token.needsRefresh(now: now.addingTimeInterval(1e9)))
        #expect(token.usable(now: now.addingTimeInterval(1e9)) == "ghu")
    }

    @Test func theTokenSurvivesTheKeychain() {
        let token = GitHubApp.Token(access: "ghu", refresh: "ghr", expires: now, refreshExpires: nil)
        #expect(GitHubApp.Token.decode(token.encoded) == token)
        #expect(GitHubApp.Token.decode("ghp_old") == nil)
        #expect(GitHubApp.Token.decode(nil) == nil)
    }

    @Test func requestsGoToGitHubAsFormsWithoutASecret() throws {
        let refresh = GitHubApp.refreshRequest(clientID: "Iv1.abc", refreshToken: "ghr_x+y")
        #expect(refresh.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(refresh.httpMethod == "POST")
        #expect(refresh.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = try #require(refresh.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body == "client_id=Iv1.abc&grant_type=refresh_token&refresh_token=ghr_x%2By")
        #expect(!body.contains("client_secret"))
        let poll = GitHubApp.pollRequest(clientID: "Iv1.abc", deviceCode: "dc")
        let pollBody = try #require(poll.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(pollBody.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(GitHubApp.deviceCodeRequest(clientID: "Iv1.abc").url?.host == "github.com")
    }

    @Test func installationsAreRead() {
        let data = Data(#"{"total_count":2,"installations":[{"id":11,"account":{"login":"me"}},{"id":22,"account":{"login":"acme"}}]}"#.utf8)
        #expect(GitHubApp.installations(from: data) == [.init(id: 11, account: "me"), .init(id: 22, account: "acme")])
    }

    @Test func theRepositoriesOfEveryInstallationMakeOneList() {
        let mine = Data(#"{"repositories":[{"full_name":"me/a","pushed_at":"2026-10-01T00:00:00Z"},{"full_name":"acme/shared","pushed_at":"2026-09-01T00:00:00Z"}]}"#.utf8)
        let acme = Data(#"{"repositories":[{"full_name":"acme/api","pushed_at":"2026-10-03T00:00:00Z"},{"full_name":"acme/shared","pushed_at":"2026-09-01T00:00:00Z"}]}"#.utf8)
        let merged = GitHubApp.mergedRepos([mine, acme, Data("oops".utf8)])
        // Each once, most recently pushed first: the same shape as /user/repos?sort=pushed.
        #expect(GitHubFeed.repoNames(from: merged) == ["acme/api", "me/a", "acme/shared"])
        #expect(GitHubFeed.repoNames(from: GitHubApp.mergedRepos([])) == [])
    }

    @Test func withoutAClientIDTheAppIsNotOffered() {
        // The test bundle has no YumiGitHubAppClientID.
        #expect(!GitHubApp.isAvailable)
    }
}
