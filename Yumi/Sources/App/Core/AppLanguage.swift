import Foundation

/// The language Yumi speaks: the Mac's by default, or the one chosen in the settings. A choice
/// is stored in `AppleLanguages` for the app only, which macOS reads at launch: it applies at
/// the next launch.
enum AppLanguage: String, CaseIterable, Sendable {
    case automatic, french, english

    static let defaultsKey = "yumiLanguage"
    private static let systemKey = "AppleLanguages"

    var code: String? {
        switch self {
        case .automatic: return nil
        case .french:    return "fr"
        case .english:   return "en"
        }
    }

    static func stored(_ defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .automatic
    }

    /// Records the choice for the next launch.
    static func choose(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: defaultsKey)
        if let code = language.code { defaults.set([code], forKey: systemKey) } else { defaults.removeObject(forKey: systemKey) }
    }

    /// English for "en", "en-GB"…; French for everything else, French being the source.
    static func resolve(_ code: String?) -> String {
        guard let code else { return "fr" }
        return code.lowercased().hasPrefix("en") ? "en" : "fr"
    }

    /// A language forced for one task: the tests say a sentence in English this way, without
    /// changing what the other tests running at the same time hear.
    @TaskLocal static var forced: String?

    /// The language of this run: "fr" or "en". The tests speak French unless they force English.
    static var current: String {
        if let forced { return resolve(forced) }
        return running
    }

    private static let running: String = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return "fr"
        }
        return resolve(Bundle.main.preferredLocalizations.first)
    }()

    static var isEnglish: Bool { current == "en" }

    /// The locale dates, times and numbers are written with: the app's language, the Mac's region.
    static var locale: Locale { locale(for: current) }

    static func locale(for language: String, region: Locale.Region? = Locale.current.region) -> Locale {
        if let region { return Locale(identifier: "\(language)_\(region.identifier)") }
        return Locale(identifier: language)
    }

    // MARK: Where the translations are

    private final class Token {}

    /// The app, or the test bundle when the tests run: both carry the compiled catalog.
    static let baseBundle = Bundle(for: Token.self)

    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["fr", "en"].map { language in
        (language, baseBundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? baseBundle)
    })

    static var bundle: Bundle { bundles[current] ?? baseBundle }
}

/// A sentence the code writes, in the language Yumi speaks. The French is the key; the English
/// is in Localization/Localizable.xcstrings.
func loc(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AppLanguage.bundle, locale: AppLanguage.locale)
}

/// The same for a key known only at run time (a label read back from a table). It must also
/// be written somewhere with `loc("…")` so that the catalog has it.
func locKey(_ key: String) -> String {
    AppLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
}
