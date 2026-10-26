import AppKit
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
        #if DEBUG
        Self.quitInstalledRelease()
        #endif

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

        Task { @MainActor in await Self.checkForUpdate() }

        logger.info("All managers started")
    }

    // MARK: - Updates

    /// Once per launch, Release builds look for a newer release on GitHub and offer to install it (UpdateClient).
    /// Debug builds don't: any release is newer, and installing it would replace the build being worked on
    @MainActor
    private static func checkForUpdate() async {
        #if !DEBUG
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let client = UpdateClient()
        guard let release = try? await client.newerRelease(than: current) else { return }

        let alert = NSAlert()
        alert.messageText = "island4mac \(release.version) is available"
        alert.informativeText = "You have \(current). Installing replaces this copy and relaunches it; settings and permissions stay."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try await client.install(release, over: Bundle.main.bundleURL)
            UpdateClient.relaunch(Bundle.main.bundleURL)
            NSApp.terminate(nil)
        } catch {
            os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
                .error("Update to \(release.version, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            let failed = NSAlert()
            failed.messageText = "Couldn't install the update"
            failed.informativeText = "\(error). Download it from GitHub and drag it into Applications instead."
            failed.addButton(withTitle: "Open Download Page")
            failed.addButton(withTitle: "Cancel")
            if failed.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
        }
        #endif
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

        #if DEBUG
        Self.reopenInstalledRelease()
        #endif
    }

    // MARK: - Dev builds

    #if DEBUG
    /// Where the installed release was when a dev build quit it. In the dev app's own defaults, so it outlives a dev
    /// build that is killed and rebuilt (Launch.command, Xcode's Stop)
    private static let steppedAsideReleaseKey = "steppedAsideRelease"

    /// A dev build is a separate app from the installed release, but there is one notch: the release quits while a
    /// dev build runs (CLAUDE.md, "Dev builds"). Waits until it has, so its hotkeys are free
    private static func quitInstalledRelease() {
        let releases = NSRunningApplication.runningApplications(withBundleIdentifier: "com.macdynamicisland.app")
        guard let path = releases.first?.bundleURL?.path else { return }
        UserDefaults.standard.set(path, forKey: steppedAsideReleaseKey)
        releases.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while releases.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// And comes back when the dev build quits; `open` runs on after this process has gone
    private static func reopenInstalledRelease() {
        guard let path = UserDefaults.standard.string(forKey: steppedAsideReleaseKey) else { return }
        UserDefaults.standard.removeObject(forKey: steppedAsideReleaseKey)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [path]
        try? open.run()
    }
    #endif
}
