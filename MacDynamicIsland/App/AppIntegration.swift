import Foundation
import os

/// Starts and stops the background monitors and services that feed the island
class AppIntegration {
    static let shared = AppIntegration()

    // MARK: - Monitors
    private var clipboardMonitor: ClipboardMonitor?
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

        // Music playback observation is wired up by IslandController
        MainActor.assumeIsolated {
            clipboardMonitor = ClipboardMonitor(store: appState.clipboardStore)
            // Something new on the clipboard shows the island for a moment
            clipboardMonitor?.onCopy = { IslandController.shared.getAppState().showIsland(reason: .clipboard) }
            clipboardMonitor?.start()
        }

        Task { @MainActor in
            let ctrl = IslandController.shared
            hotKeyMonitor = HotKeyMonitor(appState: appState, islandController: ctrl)
            hotKeyMonitor?.start()
        }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")

        // Plugins: separate processes that tell the island what to show. Agents (Claude Code, Codex and ZCode,
        // reported by island-claude-hook) is one of them, shipped in the app
        MainActor.assumeIsolated {
            PluginStore.shared.onOpen = { IslandController.shared.showPluginTab($0, hold: $1) }
            PluginStore.shared.onClose = { IslandController.shared.closePluginTab($0) }
            PluginStore.shared.start()
            Self.carryAgentSettingsOver()
        }

        logger.info("All managers started")
    }

    static let agentsPluginID = "agents"

    /// The first time the Agents plugin runs, it takes the settings of the Agents built into earlier versions
    @MainActor
    static func carryAgentSettingsOver() {
        let store = PluginStore.shared.preferences
        let settings = SettingsDefaults.shared
        let carried = "agentsPluginSettingsCarriedOver"
        guard let manifest = PluginStore.shared.installed.first(where: { $0.id == agentsPluginID })?.manifest,
              !UserDefaults.standard.bool(forKey: carried) else { return }
        let pairs: [(key: String, value: Bool)] = [
            ("sounds", settings.get(SettingsDefaults.agentSoundsEnabled)),
            ("besideNotch", settings.get(SettingsDefaults.showAgentLiveActivity)),
            ("openIsland", settings.get(SettingsDefaults.agentPromptsOpenIsland)),
        ]
        for (key, value) in pairs {
            if let preference = manifest.preferences?.first(where: { $0.key == key }) {
                store.set(.bool(value), of: preference, for: agentsPluginID)
            }
        }
        UserDefaults.standard.set(true, forKey: carried)
    }

    func stop() {
        MusicStore.shared.stop()
        MainActor.assumeIsolated { clipboardMonitor?.stop() }
        hotKeyMonitor?.stop()
        // Waits briefly for them to quit, then ends whatever is left, so no plugin outlives the app
        MainActor.assumeIsolated { PluginStore.shared.stopForQuit() }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers stopped")
    }
}
