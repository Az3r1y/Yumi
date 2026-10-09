import Foundation

/// Euros for one dollar, from the European Central Bank's reference rates: a public file, asked
/// at most once a day, with nothing sent but the request. The last rate known stays when the
/// bank cannot be reached.
enum EuroRate {
    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let askedKey = "usdToEurRateAsked"
    static let interval: TimeInterval = 24 * 3600

    /// The rate to show: the bank's last one, or `ClaudeUsageReader.defaultRate` before any.
    static func current(_ defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: ClaudeUsageReader.rateKey)
        return stored > 0 ? stored : ClaudeUsageReader.defaultRate
    }

    /// Asks the bank when the last time was a day ago or more. True when the rate changed.
    @discardableResult
    static func refresh(_ defaults: UserDefaults = .standard, now: Date = Date()) async -> Bool {
        let asked = defaults.object(forKey: askedKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(asked) >= interval else { return false }
        defaults.set(now, forKey: askedKey)
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: source, timeoutInterval: 10)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rate = euros(perDollarIn: data), rate != defaults.double(forKey: ClaudeUsageReader.rateKey) else { return false }
        defaults.set(rate, forKey: ClaudeUsageReader.rateKey)
        return true
    }

    /// The bank gives dollars for one euro (`<Cube currency='USD' rate='1.1206'/>`): its inverse.
    static func euros(perDollarIn data: Data) -> Double? {
        let text = String(decoding: data, as: UTF8.self)
        guard let match = text.firstMatch(of: /currency=['"]USD['"]\s+rate=['"]([0-9.]+)['"]/),
              let dollars = Double(match.output.1), dollars > 0.2, dollars < 5 else { return nil }
        return 1 / dollars
    }
}
