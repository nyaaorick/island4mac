import Foundation

/// A plugin's `plugin.json`: who it is and the command the app runs for it. The plugin itself is a separate
/// process that tells the island what to show in JSON lines (PluginMessage); nothing of it loads into the app
struct PluginManifest: Decodable, Equatable, Identifiable {
    /// Lowercase letters, digits, "-" and "_"; also the plugin's folder name and its tab (IslandTab.plugin)
    let id: String
    let name: String
    /// SF Symbol for its tab
    let symbol: String
    /// Program and arguments. A relative program is inside the plugin's folder (e.g. "./timer"); an absolute
    /// one is used as is (e.g. "/usr/bin/python3" with "main.py"). It runs in the plugin's folder
    let command: [String]
    /// The PluginMessage version it speaks
    let `protocol`: Int
    /// Shown in Settings and compared with the plugins repo's index to offer updates
    var version: String?
    /// Settings the island draws for it under Settings > Plugins (protocol 2)
    var preferences: [PluginPreference]?
    /// Whether it runs while its tab is on (the default) or only when needed (protocol 3)
    var lifecycle: PluginLifecycle?

    var runsOnDemand: Bool { lifecycle == .onDemand }
    /// Runs while it's turned on in Settings > Plugins, whether or not its tab is one of yours (protocol 4)
    var background: Bool?
    /// Where its compact content goes beside the notch (protocol 4); normal if it doesn't say
    var priority: PluginPriority?

    var runsInBackground: Bool { background == true }

    /// The newest PluginMessage version this app understands
    /// 2: preferences (plugin.json) and PluginEvent.preferences.
    /// 3: lifecycle "onDemand", the timeline, done and status messages, and PluginEvent.wake.
    /// 4: images on rows and compact content, row actions, and "background" and "priority" in plugin.json
    static let supportedProtocol = 4
    static let fileName = "plugin.json"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case invalidID(String)
        case emptyCommand
        case programOutsideFolder(String)
        case newerProtocol(Int)
        case invalidPreferences(String)

        var description: String {
            switch self {
            case .invalidID(let id): return "invalid id \"\(id)\""
            case .emptyCommand: return "empty command"
            case .programOutsideFolder(let path): return "program \"\(path)\" is outside the plugin's folder"
            case .newerProtocol(let version): return "needs protocol \(version), this app speaks \(supportedProtocol)"
            case .invalidPreferences(let problem): return problem
            }
        }
    }

    /// Reads and checks `plugin.json` in `folder`
    static func load(from folder: URL) throws -> PluginManifest {
        let data = try Data(contentsOf: folder.appendingPathComponent(fileName))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        try manifest.validate(in: folder)
        return manifest
    }

    func validate(in folder: URL) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        guard !id.isEmpty, id.unicodeScalars.allSatisfy(allowed.contains) else { throw LoadError.invalidID(id) }
        guard let program = command.first, !program.isEmpty else { throw LoadError.emptyCommand }
        guard `protocol` <= Self.supportedProtocol else { throw LoadError.newerProtocol(`protocol`) }
        if let problem = PluginPreference.problem(in: preferences ?? []) { throw LoadError.invalidPreferences(problem) }
        // Checked on the path as written: comparing resolved URLs breaks where the folder is reached through a
        // symlink (/var is /private/var, and standardizedFileURL drops that prefix from only some paths)
        if !program.hasPrefix("/") {
            var depth = 0
            for component in program.split(separator: "/") where component != "." {
                depth += component == ".." ? -1 : 1
                guard depth >= 0 else { throw LoadError.programOutsideFolder(program) }
            }
            guard depth > 0 else { throw LoadError.programOutsideFolder(program) }
        }
    }

    /// The program to run, resolved against the plugin's folder
    func executableURL(in folder: URL) -> URL {
        let program = command[0]
        return program.hasPrefix("/") ? URL(fileURLWithPath: program) : folder.appendingPathComponent(program).standardizedFileURL
    }
}

/// When a plugin runs
enum PluginLifecycle: String, Decodable {
    /// While its tab is on
    case persistent
    /// Only when needed: its tab opens, you tap something in it, a time it asked for comes, or its settings
    /// change. It hands the island what to show (and a timeline) and quits, and the island keeps showing it
    case onDemand
}
