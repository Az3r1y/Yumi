import Foundation

// MARK: - AppIdentity
// Single source of truth for every name and identifier the app shows, persists,
// or shares with Claude Code. Nothing else in the sources should spell these out.

enum AppIdentity {

    // MARK: Visible names

    static let productName   = "Yumi"
    static let characterName = "Mochi"

    // MARK: Persisted identifiers

    /// Keychain generic-password service. Not derived from the bundle identifier.
    static let keychainService = "app.yumi"
    /// Folder under ~/Library/Application Support (socket, hook script, inbox).
    static let supportFolderName = "Yumi"
    static let socketFileName    = "yumi.sock"
    static let hookScriptName    = "yumi-hook"
    static let inboxFolderName   = "inbox"
    /// Folder under ~/.claude that holds the hook script in the App Store build.
    static let appStoreHookFolderName = "yumi"
    /// Folder under ~/Library/Logs.
    static let logsFolderName  = "Yumi"
    static let hookLogFileName = "hooks.log"
    static let n8nLogFileName  = "n8n.log"

    // MARK: Claude Code hooks

    /// Message Claude Code receives when a permission is denied from the island.
    static let denyMessage = "Denied from \(productName)"
    /// Hook commands containing one of these were installed by the apps Yumi replaces
    /// (Coucou, NotchBuddy). They are removed when Yumi installs its own hooks.
    static let legacyHookCommandMarkers = ["NotchBuddy", "coucou"]

    // MARK: Internal

    static let notificationPrefix = "notchBuddy"

    static func notification(_ name: String) -> Notification.Name {
        Notification.Name("\(notificationPrefix).\(name)")
    }

    // MARK: Derived paths

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportFolderName)
    }

    static var inboxDirectory: URL { supportDirectory.appendingPathComponent(inboxFolderName) }

    static var socketPath: String { supportDirectory.appendingPathComponent(socketFileName).path }

    static var logsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/\(logsFolderName)")
    }

    /// Where the App Store build keeps its hook script, relative to ~/.claude.
    static var appStoreHookScriptRelativePath: String { "\(appStoreHookFolderName)/\(hookScriptName)" }

    static var hookScriptPath: String {
        #if APPSTORE
        // Written via security-scoped bookmark during hook installation
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/\(appStoreHookScriptRelativePath)").path
        #else
        return supportDirectory.appendingPathComponent(hookScriptName).path
        #endif
    }

    /// Socket path as written in the hook script. The script runs outside the app
    /// (and outside the sandbox), so the path is spelled from ~ and expanded by Python.
    static var hookScriptSocketPath: String {
        #if APPSTORE
        // The sandbox container is named after the bundle identifier
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.yumi.appstore"
        return "~/Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(supportFolderName)/\(socketFileName)"
        #else
        return "~/Library/Application Support/\(supportFolderName)/\(socketFileName)"
        #endif
    }

    // MARK: Hook command

    /// The exact command this app registers for every hook event in settings.json.
    static var hookCommand: String {
        let quoted = "\"\(hookScriptPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        #if APPSTORE
        // Sandboxed apps create quarantined files; /bin/sh bypasses the quarantine flag
        return "/bin/sh \(quoted)"
        #else
        return quoted
        #endif
    }

    /// The one place that decides whether a hook command in settings.json is ours.
    /// Exact match on purpose: a substring test on "yumi" would also catch unrelated
    /// commands (a user or a folder named yumi, for instance).
    static func isOwnHookCommand(_ command: String) -> Bool {
        command == hookCommand
    }

    /// True for a hook left behind by Coucou or NotchBuddy.
    static func isLegacyHookCommand(_ command: String) -> Bool {
        !isOwnHookCommand(command) && legacyHookCommandMarkers.contains { command.contains($0) }
    }
}
