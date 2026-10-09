import Foundation
import Security

/// The allowances as `/usage` shows them, asked to Anthropic with Claude Code's own login.
/// Asking runs no model: it costs nothing and counts against no allowance.
///
/// The token is read from the Keychain item Claude Code keeps (macOS asks the person first),
/// used for this one request to api.anthropic.com, and never written anywhere. Yumi never
/// renews it: renewing would replace Claude Code's own and could log it out. An expired token
/// waits for Claude Code to renew it.
enum ClaudeQuotaAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    /// Claude Code's access token, while it is valid; nil otherwise or when the person refused.
    static func accessToken(now: Date = Date()) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return token(from: data, now: now)
    }

    /// The access token in what Claude Code stores, unless it has expired.
    static func token(from data: Data, now: Date) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.nonEmptyTrimmed else { return nil }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: expires / 1000) <= now { return nil }
        return token
    }

    /// The five-hour and weekly allowances; nil when they could not be had.
    static func fetch(token: String) async -> (fiveHour: StatusLineRelay.Report.Allowance?, sevenDay: StatusLineRelay.Report.Allowance?)? {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Yumi", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return allowances(from: data)
    }

    /// Reads both shapes the answer has had: `five_hour` and `seven_day` objects with a
    /// `utilization` in percent, or a `limits` list with a `percent` by group.
    static func allowances(from data: Data) -> (fiveHour: StatusLineRelay.Report.Allowance?, sevenDay: StatusLineRelay.Report.Allowance?)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func allowance(_ value: Any?, percentKey: String) -> StatusLineRelay.Report.Allowance? {
            guard let entry = value as? [String: Any], let used = (entry[percentKey] as? NSNumber)?.doubleValue else { return nil }
            let resets = (entry["resets_at"] as? String).flatMap(date(from:))
            return StatusLineRelay.Report.Allowance(usedPercent: used, resetsAt: resets)
        }
        var five = allowance(object["five_hour"], percentKey: "utilization")
        var week = allowance(object["seven_day"], percentKey: "utilization")
        for limit in object["limits"] as? [[String: Any]] ?? [] {
            switch limit["group"] as? String {
            case "five_hour": five = five ?? allowance(limit, percentKey: "percent")
            case "seven_day": week = week ?? allowance(limit, percentKey: "percent")
            default: break
            }
        }
        return five == nil && week == nil ? nil : (five, week)
    }

    private static func date(from text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
