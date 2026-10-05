import Foundation
import os

/// Starts and stops the background monitors and services that feed the island
class AppIntegration {
    static let shared = AppIntegration()

    // MARK: - Monitors
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyMonitor: HotKeyMonitor?
    private var agentHookServer: AgentHookServer?

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
        clipboardMonitor = ClipboardMonitor(store: appState.clipboardStore)
        clipboardMonitor?.start()

        Task { @MainActor in
            let ctrl = IslandController.shared
            hotKeyMonitor = HotKeyMonitor(appState: appState, islandController: ctrl)
            hotKeyMonitor?.start()
        }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")

        // Claude Code, Codex and ZCode sessions, reported by island-claude-hook; every agent's hooks share one socket
        AgentHookInstaller.all.forEach { $0.refreshIfInstalled() }
        agentHookServer = AgentHookServer(socketURL: AgentHookInstaller.standard(.claude).socketURL) { event, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AgentSessionStore.shared.apply(event, reply: reply) }
            }
        }
        do {
            try agentHookServer?.start()
        } catch {
            logger.error("Agent hook server failed to start: \(String(describing: error))")
        }
        AgentSessionStore.shared.onStatusChange = { session, previous in
            AgentAlertSound.play(for: session, previous: previous)
        }
        // Claude asks you a question or for a permission: open the island on it, so you can answer there
        AgentSessionStore.shared.onPrompt = { _ in
            IslandController.shared.showAgentPrompt()
        }
        AgentSessionStore.shared.startPruning()

        // Plugins: separate processes that tell the island what to show
        MainActor.assumeIsolated { PluginStore.shared.start() }

        logger.info("All managers started")
    }

    func stop() {
        MusicStore.shared.stop()
        clipboardMonitor?.stop()
        hotKeyMonitor?.stop()
        agentHookServer?.stop()
        MainActor.assumeIsolated { PluginStore.shared.stop() }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers stopped")
    }
}
