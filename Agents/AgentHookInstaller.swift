import Foundation

/// Registers island-claude-hook for an agent's hook events in the agent's config file, next to whatever
/// hooks are already there, and keeps a copy of the helper outside the app bundle so moving or rebuilding
/// the app doesn't break the command. Every agent runs the same helper and reports to the same socket.
nonisolated struct AgentHookInstaller {
    enum InstallError: LocalizedError {
        case helperMissing
        case unreadableSettings(path: String)

        var errorDescription: String? {
            switch self {
            case .helperMissing: return "island-claude-hook is missing from the app bundle."
            case .unreadableSettings(let path): return "\(path) isn't valid JSON, so it was left alone."
            }
        }
    }

    var agent: AgentKind
    /// The agents' config files live under it; a throwaway directory in tests
    var homeURL: URL
    /// Holds the copy of the helper the agents run, and the socket
    var supportURL: URL
    var bundledHelperURL: URL

    /// Our hook entries are recognized by the helper's file name in the command
    static let helperName = "island-claude-hook"

    static func standard(_ agent: AgentKind) -> AgentHookInstaller {
        let fileManager = FileManager.default
        return AgentHookInstaller(
            agent: agent,
            homeURL: fileManager.homeDirectoryForCurrentUser,
            supportURL: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.macdynamicisland.app", isDirectory: true),
            bundledHelperURL: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(helperName)")
        )
    }

    static var all: [AgentHookInstaller] { AgentKind.allCases.map(standard) }

    /// The file the agent reads its hooks from
    var settingsURL: URL {
        switch agent {
        case .claude: return homeURL.appendingPathComponent(".claude/settings.json")
        case .codex: return homeURL.appendingPathComponent(".codex/hooks.json")
        case .zcode: return homeURL.appendingPathComponent(".zcode/cli/config.json")
        }
    }

    /// The copy of the helper the agents run
    var helperURL: URL { supportURL.appendingPathComponent(Self.helperName) }
    /// Short name: Unix socket paths are limited to 104 bytes
    var socketURL: URL { supportURL.appendingPathComponent("hook.sock") }

    /// Events the island listens to: the ones the agent has out of Claude Code's
    var events: [String] {
        switch agent {
        case .claude:
            return [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionRequest", "PermissionDenied", "Notification",
                "Stop", "StopFailure", "SubagentStart", "SubagentStop",
                "TaskCreated", "TaskCompleted", "PreCompact", "PostCompact",
            ]
        case .codex:
            return [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PostToolUse", "PermissionRequest",
                "Stop", "Interrupt", "SubagentStart", "SubagentStop",
                "PreCompact", "PostCompact",
            ]
        case .zcode:
            return [
                "SessionStart", "UserPromptSubmit",
                "PreToolUse", "PostToolUse", "PostToolUseFailure",
                "PermissionRequest", "Stop",
            ]
        }
    }

    /// The command the agent runs, through /bin/sh; the helper tells the island which agent it ran for
    var command: String {
        "\(Self.shellQuoted(helperURL.path)) \(Self.shellQuoted(socketURL.path)) \(agent.rawValue)"
    }

    /// The command for one event: Claude Code's PermissionRequest hook waits for the island's reply,
    /// which is how the island answers Claude's questions
    func command(for event: String) -> String {
        Self.waitsForReply(agent: agent, event: event) ? command + " wait" : command
    }

    private static func waitsForReply(agent: AgentKind, event: String) -> Bool {
        agent == .claude && event == AgentHookEvent.Kind.permissionRequest.rawValue
    }

    /// How long a waiting hook may wait for your answer; island-claude-hook gives up at the same time
    static let replyTimeout = 24 * 60 * 60

    /// Whether the agent has been used on this Mac, going by the folder its config file lives in
    var isAgentPresent: Bool {
        FileManager.default.fileExists(atPath: settingsURL.deletingLastPathComponent().path)
    }

    var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return containsOurHooks(settings)
    }

    func install() throws {
        try copyHelper()
        let settings = try readSettings()
        let updated = self.settings(settings, withHooksFor: events)
        if !NSDictionary(dictionary: updated).isEqual(to: settings) {
            try writeSettings(updated)
        }
    }

    func uninstall() throws {
        let settings = try readSettings()
        if containsOurHooks(settings) {
            try writeSettings(self.settings(settings, withHooksFor: []))
        }
        // Another agent may still run the helper
        let helperInUse = AgentKind.allCases.contains { $0 != agent && installer(for: $0).isInstalled }
        if !helperInUse {
            try? FileManager.default.removeItem(at: helperURL)
        }
    }

    /// After an update or rebuild, keep the installed helper and hook command in step with this app
    func refreshIfInstalled() {
        guard isInstalled else { return }
        try? install()
    }

    private func installer(for other: AgentKind) -> AgentHookInstaller {
        var installer = self
        installer.agent = other
        return installer
    }

    // MARK: - Config file

    /// Adds our hook to each of `events` and removes it from every other event, leaving other hooks alone
    func settings(_ settings: [String: Any], withHooksFor events: [String]) -> [String: Any] {
        var hooks = hookTable(in: settings)

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !Self.isOurs($0) }
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
            groups.append(hookGroup(for: event))
            hooks[event] = groups
        }

        return self.settings(settings, replacingHookTableWith: hooks, addingOurs: !events.isEmpty)
    }

    /// Our entry under an event
    private func hookGroup(for event: String) -> [String: Any] {
        let command = command(for: event)
        if Self.waitsForReply(agent: agent, event: event) {
            // In the foreground, so Claude Code reads the island's answer. It shows its own prompt meanwhile,
            // and the island lets the hook go at once for anything but a question it can answer.
            return ["matcher": "*", "hooks": [["type": "command", "command": command, "timeout": Self.replyTimeout]]]
        }
        switch agent {
        case .claude:
            // In the background, so the island never slows Claude Code down
            return ["matcher": "*", "hooks": [["type": "command", "command": command, "async": true]]]
        case .codex, .zcode:
            // Without a matcher it runs for everything ("*" isn't a valid pattern to ZCode). They run it in the
            // foreground, which is fine: the helper returns in milliseconds and gives up after 3 seconds.
            return ["hooks": [["type": "command", "command": command, "timeout": 5]]]
        }
    }

    /// Event name → matcher groups. ZCode nests them under hooks.events, next to its hook options.
    private func hookTable(in settings: [String: Any]) -> [String: Any] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return agent == .zcode ? hooks["events"] as? [String: Any] ?? [:] : hooks
    }

    private func settings(_ settings: [String: Any], replacingHookTableWith table: [String: Any], addingOurs: Bool) -> [String: Any] {
        var settings = settings
        guard agent == .zcode else {
            settings["hooks"] = table.isEmpty ? nil : table
            return settings
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["events"] = table.isEmpty ? nil : table
        if addingOurs {
            // ZCode skips the hooks in its config file unless they're turned on
            hooks["enabled"] = true
        } else if table.isEmpty {
            // Nothing left for the switch we turned on to run
            hooks["enabled"] = nil
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    private func containsOurHooks(_ settings: [String: Any]) -> Bool {
        hookTable(in: settings).values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: Self.isOurs)
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
            throw InstallError.unreadableSettings(path: (settingsURL.path as NSString).abbreviatingWithTildeInPath)
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
