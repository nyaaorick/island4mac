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

    /// The newest PluginMessage version this app understands
    static let supportedProtocol = 1
    static let fileName = "plugin.json"

    enum LoadError: Error, Equatable, CustomStringConvertible {
        case invalidID(String)
        case emptyCommand
        case programOutsideFolder(String)
        case newerProtocol(Int)

        var description: String {
            switch self {
            case .invalidID(let id): return "invalid id \"\(id)\""
            case .emptyCommand: return "empty command"
            case .programOutsideFolder(let path): return "program \"\(path)\" is outside the plugin's folder"
            case .newerProtocol(let version): return "needs protocol \(version), this app speaks \(supportedProtocol)"
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
