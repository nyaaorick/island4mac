import Foundation
import os

/// Starts and stops the background monitors and services that feed the island
class AppIntegration {
    static let shared = AppIntegration()

    // MARK: - Monitors
    private var hotKeyMonitor: HotKeyMonitor?

    private init() {}

    // MARK: - Initialization

    func initialize() {
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("Initializing app integration...")

        // Log memory usage at launch
        MemoryUsageService.shared.logMemoryUsage()

        logger.info("App integration complete")
    }

    // MARK: - Lifecycle

    func start() {
        let appState = MainActor.assumeIsolated { // ✅ MainActor isolation fix
            IslandController.shared.getAppState()
        }

        Task { @MainActor in
            let ctrl = IslandController.shared
            hotKeyMonitor = HotKeyMonitor(appState: appState, islandController: ctrl)
            hotKeyMonitor?.start()
        }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")

        // Plugins: separate processes that tell the island what to show. Music, Clipboard, Files and Agents (Claude
        // Code, Codex and ZCode, reported by island-claude-hook) are plugins too, shipped in the app
        MainActor.assumeIsolated {
            PluginStore.shared.onOpen = { IslandController.shared.showPluginTab($0, hold: $1) }
            PluginStore.shared.onClose = { IslandController.shared.closePluginTab($0) }
            PluginStore.shared.start()
            Self.carrySettingsOver()
        }

        logger.info("All managers started")
    }

    static let agentsPluginID = "agents"

    /// The first time each bundled plugin runs, it takes the settings of the version built into earlier apps
    @MainActor
    static func carrySettingsOver() {
        let settings = SettingsDefaults.shared
        carry(to: agentsPluginID, [
            ("sounds", .bool(settings.get(SettingsDefaults.agentSoundsEnabled))),
            ("besideNotch", .bool(settings.get(SettingsDefaults.showAgentLiveActivity))),
            ("openIsland", .bool(settings.get(SettingsDefaults.agentPromptsOpenIsland))),
        ], doneKey: "agentsPluginSettingsCarriedOver")
        carry(to: "clipboard", [
            ("maxItems", .number(Double(settings.get(SettingsDefaults.clipboardMaxItems)))),
            ("keepHours", .number(Double(settings.get(SettingsDefaults.clipboardKeepHours)))),
        ], doneKey: "clipboardPluginSettingsCarriedOver")
        carry(to: "music", [
            ("lyricsSource", .string(settings.get(SettingsDefaults.lyricsSource))),
        ], doneKey: "musicPluginSettingsCarriedOver")
    }

    @MainActor
    private static func carry(to pluginID: String, _ pairs: [(key: String, value: PluginPreferenceValue)], doneKey: String) {
        let store = PluginStore.shared.preferences
        guard let manifest = PluginStore.shared.installed.first(where: { $0.id == pluginID })?.manifest,
              !UserDefaults.standard.bool(forKey: doneKey) else { return }
        for (key, value) in pairs {
            if let preference = manifest.preferences?.first(where: { $0.key == key }) {
                store.set(value, of: preference, for: pluginID)
            }
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    func stop() {
        hotKeyMonitor?.stop()
        // Waits briefly for them to quit, then ends whatever is left, so no plugin outlives the app
        MainActor.assumeIsolated { PluginStore.shared.stopForQuit() }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers stopped")
    }
}
