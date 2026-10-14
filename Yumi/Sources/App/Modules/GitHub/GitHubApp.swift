import Foundation

/// The Yumi GitHub App: a way in that follows every account where the person installed it
/// (theirs and as many organisations as they like), where a fine-grained token sees one owner.
///
/// No server: the person signs in with the device flow (a code typed on github.com), which
/// needs only the app's public Client ID. The user access token lasts eight hours and is
/// renewed with its refresh token, without any secret, because it came from the device flow.
/// Only github.com and api.github.com are asked.
enum GitHubApp {
    /// The Client ID of the registered app, from `YumiGitHubAppClientID` in Info.plist
    /// (project.yml). Empty until the maintainer registers the app: the option is then hidden.
    static var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "YumiGitHubAppClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isAvailable: Bool { !clientID.isEmpty }

    /// Where the person installs the app on more accounts, from `YumiGitHubAppSlug`.
    static var installURL: URL? {
        let slug = (Bundle.main.object(forInfoDictionaryKey: "YumiGitHubAppSlug") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? nil : URL(string: "https://github.com/apps/\(slug)/installations/new")
    }

    /// The Keychain key of the user access token and its refresh token, as JSON.
    static let tokenKey = "github-app-token"

    // MARK: Requests

    static func deviceCodeRequest(clientID: String) -> URLRequest {
        form("https://github.com/login/device/code", ["client_id": clientID])
    }

    static func pollRequest(clientID: String, deviceCode: String) -> URLRequest {
        form("https://github.com/login/oauth/access_token",
             ["client_id": clientID, "device_code": deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        form("https://github.com/login/oauth/access_token",
             ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    private static func form(_ address: String, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    // MARK: Answers

    /// What github.com gives to start the device flow.
    struct DeviceCode: Equatable, Sendable {
        var deviceCode: String
        /// The code the person types, like "WDJB-MJHT".
        var userCode: String
        var verificationURL: URL
        /// When the code stops working.
        var expires: Date
        /// Seconds between two polls.
        var interval: TimeInterval
    }

    static func deviceCode(from data: Data, now: Date) -> DeviceCode? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device_code"] as? String, !device.isEmpty,
              let user = object["user_code"] as? String, !user.isEmpty else { return nil }
        // Only github.com: a verification address elsewhere is not opened.
        let url = (object["verification_uri"] as? String).flatMap(URL.init(string:))
            .flatMap { $0.host == "github.com" ? $0 : nil } ?? URL(string: "https://github.com/login/device")!
        let expiresIn = number(object["expires_in"]) ?? 900
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: url,
                          expires: now.addingTimeInterval(expiresIn), interval: max(5, number(object["interval"]) ?? 5))
    }

    /// One answer of the token endpoint, while polling or renewing.
    enum Poll: Equatable, Sendable {
        case token(Token)
        /// The person has not typed the code yet.
        case pending
        /// Polled too fast: wait this long between polls from now on.
        case slowDown(TimeInterval)
        /// The code expired: start again.
        case expired
        /// The person cancelled on github.com.
        case denied
        /// Anything else, with GitHub's error code.
        case failed(String)
    }

    static func poll(from data: Data, now: Date) -> Poll {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed("unreadable") }
        if let access = object["access_token"] as? String, !access.isEmpty {
            return .token(Token(access: access,
                                refresh: (object["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                expires: number(object["expires_in"]).map { now.addingTimeInterval($0) },
                                refreshExpires: number(object["refresh_token_expires_in"]).map { now.addingTimeInterval($0) }))
        }
        switch object["error"] as? String ?? "" {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(max(5, number(object["interval"]) ?? 10))
        case "expired_token", "token_expired": return .expired
        case "access_denied": return .denied
        case let other: return .failed(other.isEmpty ? "unknown" : other)
        }
    }

    /// GitHub sends numbers as numbers, older answers sometimes as text.
    private static func number(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return TimeInterval(value) }
        return nil
    }

    // MARK: The token

    /// A user access token of the app, kept in the Keychain as JSON.
    struct Token: Codable, Equatable, Sendable {
        var access: String
        var refresh: String?
        /// nil when the app was set not to expire its tokens.
        var expires: Date?
        var refreshExpires: Date?

        /// Renewed a little before the end, so a look never starts with a token about to die.
        static let margin: TimeInterval = 5 * 60

        func needsRefresh(now: Date) -> Bool {
            guard let expires else { return false }
            return now >= expires.addingTimeInterval(-Self.margin)
        }

        /// True while the refresh token still works.
        func canRefresh(now: Date) -> Bool {
            guard refresh != nil else { return false }
            guard let refreshExpires else { return true }
            return now < refreshExpires
        }

        /// The token to send now: nil once it expired and cannot be renewed (sign in again).
        func usable(now: Date) -> String? {
            if let expires, now >= expires, !canRefresh(now: now) { return nil }
            return access
        }

        var encoded: String? { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } }

        static func decode(_ text: String?) -> Token? {
            guard let data = text?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Token.self, from: data)
        }
    }

    // MARK: Installations

    /// The accounts where the app is installed, from `/user/installations`.
    struct Installation: Equatable, Sendable {
        var id: Int64
        var account: String
    }

    static func installations(from data: Data) -> [Installation] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["installations"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = (item["id"] as? NSNumber)?.int64Value else { return nil }
            return Installation(id: id, account: (item["account"] as? [String: Any])?["login"] as? String ?? "")
        }
    }

    /// The repositories of every installation (`/user/installations/{id}/repositories`), as one
    /// list shaped like `/user/repos?sort=pushed`: each repository once, most recently pushed
    /// first. The module then reads it with the same code as a personal token's list.
    static func mergedRepos(_ pages: [Data]) -> Data {
        var byName: [String: [String: Any]] = [:]
        for page in pages {
            guard let object = try? JSONSerialization.jsonObject(with: page) as? [String: Any],
                  let items = object["repositories"] as? [[String: Any]] else { continue }
            for item in items {
                guard let name = item["full_name"] as? String else { continue }
                byName[name] = item
            }
        }
        let sorted = byName.values.sorted { a, b in
            let left = a["pushed_at"] as? String ?? "", right = b["pushed_at"] as? String ?? ""
            // ISO 8601 in UTC sorts as text
            return left != right ? left > right : (a["full_name"] as? String ?? "") < (b["full_name"] as? String ?? "")
        }
        return (try? JSONSerialization.data(withJSONObject: sorted)) ?? Data("[]".utf8)
    }
}
