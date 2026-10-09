import AppKit
import UniformTypeIdentifiers

/// Opening things on the Mac, seen from the agent. `WorkspaceOpener` uses `NSWorkspace`.
protocol Opener: Sendable {
    /// An installed app by its name ("Xcode", "safari"), or nil.
    func application(named name: String) -> URL?
    /// Opens a page, a file or a folder, with an app when one is given; an app alone is launched.
    func open(_ target: URL?, with app: URL?) async throws
    func isRunning(_ app: URL) -> Bool
}

/// Opens an app, a web page, or a file or folder (a project) with an app. Never runs a program,
/// a script or an installer it was given as a file: apps are found by their name only.
struct OpenTool: Tool {
    var opener: any Opener
    var home: String = NSHomeDirectory()
    /// Where a project named without its path is looked for, two levels down.
    var projectFolders = ["Developer", "Projects", "Work", "Code", "src", "Documents", "Desktop"]
    /// What would run something rather than open it, besides what the system types say runs
    /// (`isRunnable`): links that can point at a program, plug-ins, installers.
    static let runnable: Set<String> = ["app", "command", "sh", "zsh", "bash", "csh", "tool", "pkg", "mpkg", "dmg", "terminal",
                                        "scpt", "scptd", "applescript", "workflow", "action", "shortcut", "py", "rb", "pl",
                                        "jar", "prefpane", "fileloc", "inetloc", "webloc", "url", "desktop", "osax", "kext",
                                        "plugin", "bundle", "framework", "xpc", "appex", "saver", "systemextension",
                                        "dylib", "so", "exe", "msi", "iso", "configprofile", "mobileconfig"]
    /// Apps that run the files they are given: a folder may open in them, never a file.
    static let runners: Set<String> = ["com.apple.terminal", "com.googlecode.iterm2", "com.apple.scripteditor2",
                                       "com.apple.automator", "com.apple.installer", "org.python.pythonlauncher",
                                       "com.mitchellh.ghostty", "dev.warp.warp-stable", "net.kovidgoyal.kitty",
                                       "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "com.apple.shortcuts"]
    static let runnerNames: Set<String> = ["terminal", "iterm", "script editor", "éditeur de script", "automator", "installer",
                                           "programme d'installation", "python launcher", "ghostty", "warp", "kitty",
                                           "alacritty", "wezterm", "hyper", "shortcuts", "raccourcis"]

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "open_item",
            name: loc("Open an app, a page or a project"),
            description: "Opens an installed app by its name, a web page (http or https), or a file or folder, optionally with a given app (\"open Yumi in Xcode\": target Yumi, app Xcode).",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "target", type: .string, required: false,
                      description: "an https URL, a path (~/Work/Yumi), or the name of a project folder; omit to just launch the app"),
                .init(name: "app", type: .string, required: false, description: "the name of an installed app to open it with, or to launch"),
            ]),
            risk: .write,
            outputKeys: ["opened", "reply"])
    }

    /// What will be opened, worked out from the arguments.
    struct Plan {
        enum Target: Equatable { case page(URL), item(String) }
        var target: Target?
        var app: (name: String, url: URL)?
    }

    func action(for arguments: ToolArguments) -> ToolAction? {
        guard let plan = try? plan(arguments) else { return nil }
        var resources: [ResourceRef] = []
        var content: String?
        switch plan.target {
        case .page(let url)?:
            resources.append(ResourceRef(.url, url.absoluteString))
            // The permission keeps the site only: the person reads the whole address here
            content = url.absoluteString
        case .item(let path)?:
            resources.append(.file(path))
        case nil:
            break
        }
        // Always one unknown resource: what opens a file depends on the app, so no answer is
        // remembered for a whole project or site
        resources.append(ResourceRef(.unknown, plan.app.map { loc("l'app \($0.name)") } ?? loc("avec l'app par défaut")))
        return ToolAction(kind: .run, resources: resources, reversible: true, content: content)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        do { _ = try plan(arguments) } catch { return error.reason }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let plan = try plan(arguments)
        try Task.checkCancellation()
        let target: URL? = switch plan.target {
        case .page(let url)?: url
        case .item(let path)?: URL(fileURLWithPath: path)
        case nil: nil
        }
        do {
            try await opener.open(target, with: plan.app?.url)
        } catch {
            throw ToolError.failed(loc("macOS n'a pas pu l'ouvrir : \(error.localizedDescription)"))
        }
        let what = describe(plan)
        return ToolOutput(summary: "Opened \(what).",
                          values: ["opened": .string(what), "reply": .string(loc("J'ai ouvert \(what)."))])
    }

    /// An app that was asked for is running.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard let app = (try? plan(arguments))?.app else { return nil }
        // An app takes a moment to start
        for _ in 0..<20 {
            if opener.isRunning(app.url) { return nil }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return loc("\(app.name) ne tourne pas")
    }

    // MARK: - Reading the arguments

    func plan(_ arguments: ToolArguments) throws(ToolError) -> Plan {
        var plan = Plan()
        if case .string(let raw)? = arguments["app"], let name = raw.nonEmptyTrimmed {
            guard let url = opener.application(named: name) else {
                throw .invalidInput(loc("je ne trouve pas d'app « \(name) » sur ce Mac"))
            }
            plan.app = (url.deletingPathExtension().lastPathComponent, url)
        }
        if case .string(let raw)? = arguments["target"], let target = raw.nonEmptyTrimmed {
            plan.target = try resolve(target)
        }
        guard plan.target != nil || plan.app != nil else { throw .invalidInput(loc("il manque ce qu'il faut ouvrir")) }
        if case .item(let path)? = plan.target, let app = plan.app, !isFolder(path), isRunner(app.url, name: app.name) {
            throw .invalidInput(loc("je n'ouvre pas de fichier dans \(app.name) : il l'exécuterait"))
        }
        return plan
    }

    private func resolve(_ raw: String) throws(ToolError) -> Plan.Target {
        let lower = raw.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: raw), url.host?.isEmpty == false else {
                throw .invalidInput(loc("« \(raw) » n'est pas une adresse web valable"))
            }
            return .page(url)
        }
        if lower.contains("://") || lower.hasPrefix("file:") || lower.hasPrefix("javascript:") {
            throw .invalidInput(loc("je n'ouvre que des pages web, des fichiers et des dossiers"))
        }
        let given: String
        if raw == "~" || raw.hasPrefix("~/") || raw.hasPrefix("/") {
            given = raw.hasPrefix("~") ? home + raw.dropFirst() : raw
        } else if !raw.contains("/"), let project = project(named: raw) {
            given = project
        } else {
            throw .invalidInput(loc("je ne trouve pas « \(raw) ». Donne-moi son chemin, par exemple ~/Work/\(raw)"))
        }
        // What is checked and opened is what a link points to, not the link: a « notes.md » that
        // leads to an app would launch it
        let path = URL(fileURLWithPath: given).standardizedFileURL.resolvingSymlinksInPath().path
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else {
            throw .invalidInput(loc("\(display(path)) n'existe pas"))
        }
        // A folder that is a bundle (an app, an installer) would run, not open
        if isRunnable(path, isFolder: isFolder.boolValue) {
            throw .invalidInput(loc("je n'ouvre pas \(display(path)) : il lancerait un programme. Pour une app, donne-moi son nom"))
        }
        return .item(path)
    }

    /// Opening it would run code: by its extension, its system type, or its execute permission.
    private func isRunnable(_ path: String, isFolder: Bool) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if Self.runnable.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext),
           [UTType.executable, .application, .bundle, .script, .shellScript, .unixExecutable].contains(where: type.conforms(to:)) {
            return true
        }
        return !isFolder && FileManager.default.isExecutableFile(atPath: path)
    }

    private func isFolder(_ path: String) -> Bool {
        var folder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &folder) && folder.boolValue
    }

    private func isRunner(_ app: URL, name: String) -> Bool {
        if let id = Bundle(url: app)?.bundleIdentifier?.lowercased(), Self.runners.contains(id) { return true }
        let lower = name.lowercased()
        return Self.runnerNames.contains { lower == $0 || lower.hasPrefix($0 + " ") }
    }

    /// A folder of that name in the usual places for projects, one or two levels down.
    private func project(named name: String) -> String? {
        let manager = FileManager.default
        for folder in projectFolders {
            let root = (home as NSString).appendingPathComponent(folder)
            guard let children = try? manager.contentsOfDirectory(atPath: root) else { continue }
            if let hit = children.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return (root as NSString).appendingPathComponent(hit)
            }
            for child in children where !child.hasPrefix(".") {
                let inner = (root as NSString).appendingPathComponent(child)
                if let hit = (try? manager.contentsOfDirectory(atPath: inner))?.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    let path = (inner as NSString).appendingPathComponent(hit)
                    var isFolder: ObjCBool = false
                    if manager.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue { return path }
                }
            }
        }
        return nil
    }

    private func describe(_ plan: Plan) -> String {
        let target: String? = switch plan.target {
        case .page(let url)?: url.host ?? url.absoluteString
        case .item(let path)?: display(path)
        case nil: nil
        }
        switch (target, plan.app?.name) {
        case let (target?, app?): return loc("\(target) dans \(app)")
        case let (target?, nil): return target
        case let (nil, app?): return app
        case (nil, nil): return ""
        }
    }

    private func display(_ path: String) -> String {
        RiskAssessor.path(path, isInside: home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// The real Mac.
struct WorkspaceOpener: Opener {
    /// Where apps are installed, in this order.
    static let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                          "/Applications/Utilities", NSHomeDirectory() + "/Applications"]

    func application(named name: String) -> URL? {
        let wanted = name.lowercased().hasSuffix(".app") ? String(name.dropLast(4)) : name
        for folder in Self.folders {
            guard let apps = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            if let hit = apps.first(where: { $0.hasSuffix(".app") && String($0.dropLast(4)).caseInsensitiveCompare(wanted) == .orderedSame }) {
                return URL(fileURLWithPath: folder).appendingPathComponent(hit)
            }
        }
        return nil
    }

    func open(_ target: URL?, with app: URL?) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        switch (target, app) {
        case let (target?, app?): _ = try await NSWorkspace.shared.open([target], withApplicationAt: app, configuration: configuration)
        case let (target?, nil): _ = try await NSWorkspace.shared.open(target, configuration: configuration)
        case let (nil, app?): _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        case (nil, nil): break
        }
    }

    func isRunning(_ app: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
    }
}
