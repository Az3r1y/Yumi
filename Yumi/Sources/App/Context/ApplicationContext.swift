import Foundation

/// One application as the Context Engine sees it: what macOS says about it, nothing more.
struct ApplicationContext: Hashable, Codable, Sendable {
    /// Empty when the application has none (a bare executable).
    var bundleID: String
    var name: String
    var processID: Int32
    /// What the application declares in its Info.plist (`LSApplicationCategoryType`). nil when it declares nothing.
    var category: ApplicationCategory?

    init(bundleID: String, name: String, processID: Int32, category: ApplicationCategory? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.processID = processID
        self.category = category
    }

    /// Two observations are the same application when they are the same process.
    func isSameApplication(as other: ApplicationContext?) -> Bool {
        guard let other else { return false }
        return processID == other.processID && bundleID == other.bundleID
    }

    /// The key used to merge relaunches of one application in the recent list.
    var identity: String { bundleID.isEmpty ? name : bundleID }
}

/// The category an application gives itself, as an Apple uniform type identifier
/// (`public.app-category.developer-tools`). Read from the application, never guessed.
struct ApplicationCategory: Hashable, Codable, Sendable {
    let identifier: String

    init(_ identifier: String) { self.identifier = identifier }

    /// A short name for the debug panel. Unknown identifiers show their last component.
    var label: String {
        let short = identifier.replacingOccurrences(of: "public.app-category.", with: "")
        return Self.labels[short] ?? short
    }

    /// The categories Apple publishes for `LSApplicationCategoryType`, the most common ones.
    private static let labels: [String: String] = [
        "developer-tools": "Developer tools",
        "productivity": "Productivity",
        "utilities": "Utilities",
        "graphics-design": "Design",
        "photography": "Photography",
        "video": "Video",
        "music": "Music",
        "social-networking": "Communication",
        "business": "Business",
        "education": "Education",
        "entertainment": "Entertainment",
        "news": "News",
        "reference": "Reference",
        "finance": "Finance",
        "games": "Games",
        "lifestyle": "Lifestyle",
    ]
}
