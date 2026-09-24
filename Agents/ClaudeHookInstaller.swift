import Foundation

/// Registers island-claude-hook for Claude Code's hook events in ~/.claude/settings.json,
/// next to whatever hooks are already there, and keeps a copy of the helper outside the app
/// bundle so moving or rebuilding the app doesn't break the command.
nonisolated struct ClaudeHookInstaller {
    enum InstallError: LocalizedError {
        case helperMissing
        case unreadableSettings

        var errorDescription: String? {
            switch self {
            case .helperMissing: return "island-claude-hook is missing from the app bundle."
            case .unreadableSettings: return "~/.claude/settings.json isn't valid JSON, so it was left alone."
            }
        }
    }

    var settingsURL: URL
    /// The copy of the helper Claude Code runs
    var helperURL: URL
    var socketURL: URL
    var bundledHelperURL: URL

    /// Events the island listens to
    static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "PermissionDenied", "Notification",
        "Stop", "StopFailure", "SubagentStart", "SubagentStop",
        "TaskCreated", "TaskCompleted", "PreCompact", "PostCompact",
    ]

    /// Our hook entries are recognized by the helper's file name in the command
    static let helperName = "island-claude-hook"

    static var standard: ClaudeHookInstaller {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.macdynamicisland.app", isDirectory: true)
        return ClaudeHookInstaller(
            settingsURL: fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
            helperURL: support.appendingPathComponent(helperName),
            // Short name: Unix socket paths are limited to 104 bytes
            socketURL: support.appendingPathComponent("hook.sock"),
            bundledHelperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(helperName)")
        )
    }

    /// The command Claude Code runs, through /bin/sh
    var command: String {
        "\(Self.shellQuoted(helperURL.path)) \(Self.shellQuoted(socketURL.path))"
    }

    var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return Self.containsOurHooks(settings)
    }

    func install() throws {
        try copyHelper()
        let settings = try readSettings()
        let updated = Self.settings(settings, withHooksFor: Self.events, command: command)
        if !NSDictionary(dictionary: updated).isEqual(to: settings) {
            try writeSettings(updated)
        }
    }

    func uninstall() throws {
        let settings = try readSettings()
        if Self.containsOurHooks(settings) {
            try writeSettings(Self.settings(settings, withHooksFor: [], command: command))
        }
        try? FileManager.default.removeItem(at: helperURL)
    }

    /// After an update or rebuild, keep the installed helper and hook command in step with this app
    func refreshIfInstalled() {
        guard isInstalled else { return }
        try? install()
    }

    // MARK: - settings.json

    /// Adds our hook to each of `events` and removes it from every other event, leaving other hooks alone
    static func settings(_ settings: [String: Any], withHooksFor events: [String], command: String) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !isOurs($0) }
                if others.isEmpty && !handlers.isEmpty { return nil }
                var group = group
                group["hooks"] = others
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }

        for event in events {
            // Leave an entry we can't make sense of as it is
            if let existing = hooks[event], !(existing is [[String: Any]]) { continue }
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append([
                "matcher": "*",
                // In the background, so the island never slows Claude Code down
                "hooks": [["type": "command", "command": command, "async": true]],
            ])
            hooks[event] = groups
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    private static func containsOurHooks(_ settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    private static func isOurs(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(helperName) == true
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return settings
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Keep the file as it was before the island first touched it
        let backup = settingsURL.appendingPathExtension("mac-island-backup")
        if fileManager.fileExists(atPath: settingsURL.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: settingsURL, to: backup)
        }

        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(UInt8(ascii: "\n"))
        try data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Helper

    private func copyHelper() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: bundledHelperURL.path) else { throw InstallError.helperMissing }
        if fileManager.contentsEqual(atPath: bundledHelperURL.path, andPath: helperURL.path) { return }

        try fileManager.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = helperURL.appendingPathExtension("new")
        try? fileManager.removeItem(at: staging)
        try fileManager.copyItem(at: bundledHelperURL, to: staging)
        // Swap in place, so a hook running right now sees either the old or the new helper
        if fileManager.fileExists(atPath: helperURL.path) {
            _ = try fileManager.replaceItemAt(helperURL, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: helperURL)
        }
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
