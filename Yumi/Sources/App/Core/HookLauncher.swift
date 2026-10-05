import Foundation

/// The hook Claude Code runs is a small `/bin/sh` launcher next to the Python relay. On a Mac
/// without the Command Line Tools, `/usr/bin/python3` is only a stub that opens their installer
/// and fails: run by every hook event, it would show that window again and again and put an
/// error in every Claude Code turn. The launcher looks for a real python3 first and, without
/// one, lets Claude Code carry on as if Yumi were not there.
enum HookLauncher {
    static let relayName = "yumi-hook-relay.py"

    /// Pythons that do not need the Command Line Tools: Homebrew (Apple silicon, Intel), python.org.
    static let standalonePythons = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                                    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"]

    static var script: String { script() }

    /// - Parameters: the places to look, replaceable by the tests.
    static func script(pythons: [String] = standalonePythons, systemPython: String = "/usr/bin/python3",
                       toolsCheck: String = "/usr/bin/xcode-select -p") -> String {
        """
        #!/bin/sh
        # \(AppIdentity.hookScriptName): starts \(AppIdentity.productName)'s hook relay with a python3 that works.
        # Never starts the Command Line Tools installer; without python3 it exits at once, silently.
        relay="$(dirname "$0")/\(relayName)"
        for python in \(pythons.joined(separator: " ")); do
          if [ -x "$python" ]; then exec "$python" "$relay"; fi
        done
        # /usr/bin/python3 works only once the Command Line Tools (or Xcode) are installed.
        if \(toolsCheck) >/dev/null 2>&1 && [ -x \(systemPython) ]; then exec \(systemPython) "$relay"; fi
        cat >/dev/null
        exit 0

        """
    }

    /// The same search as the launcher, for the app to say it before Claude Code is affected.
    static func pythonAvailable(isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:),
                                developerToolsInstalled: () -> Bool = HookLauncher.developerToolsInstalled) -> Bool {
        standalonePythons.contains(where: isExecutable) || (isExecutable("/usr/bin/python3") && developerToolsInstalled())
    }

    /// `xcode-select -p` succeeds once the Command Line Tools or Xcode are there. It never opens a window.
    static func developerToolsInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static let missingPython = "python3 manque : les sessions Claude Code ne s'afficheront pas dans l'encoche (Claude Code fonctionne normalement). Installe les outils de ligne de commande avec « xcode-select --install » dans le Terminal."
}
