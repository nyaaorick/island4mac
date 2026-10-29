import AppKit
import os

/// Starts and stops what feeds the island: the hotkeys, the plugins (Music, Clipboard, Files and Agents among them),
/// and in Release builds the update check
final class AppIntegration {
    static let shared = AppIntegration()

    private var hotKeyMonitor: HotKeyMonitor?
    private let logger = Logger(subsystem: Log.subsystem, category: "AppIntegration")

    private init() {}

    func start() {
        #if DEBUG
        Self.quitInstalledRelease()
        #endif
        MainActor.assumeIsolated {
            let controller = IslandController.shared
            hotKeyMonitor = HotKeyMonitor(appState: controller.getAppState(), islandController: controller)
            hotKeyMonitor?.start()
            // Plugins are separate processes that tell the island what to show; the bundled ones ship in the app
            PluginStore.shared.onOpen = { IslandController.shared.showPluginTab($0, hold: $1) }
            PluginStore.shared.onClose = { IslandController.shared.closePluginTab($0) }
            PluginStore.shared.start()
        }
        Task { @MainActor in
            await Self.checkForUpdate()
            // The catalog, so Settings > Plugins can show at once which plugins have updates
            await PluginCatalogStore.shared.refreshIfStale()
        }
        logger.info("Started")
    }

    func stop() {
        hotKeyMonitor?.stop()
        // Waits briefly for them to quit, then ends whatever is left, so no plugin outlives the app
        MainActor.assumeIsolated { PluginStore.shared.stopForQuit() }
        logger.info("Stopped")
        #if DEBUG
        Self.reopenInstalledRelease()
        #endif
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
            Logger(subsystem: Log.subsystem, category: "AppIntegration")
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

    // MARK: - Dev builds

    #if DEBUG
    /// Where the installed release was when a dev build quit it. In the dev app's own defaults, so it outlives a dev
    /// build that is killed and rebuilt (Launch.command, Xcode's Stop)
    private static let steppedAsideReleaseKey = "steppedAsideRelease"

    /// A dev build is a separate app from the installed release, but there is one notch: the release quits while a
    /// dev build runs. Waits until it has, so its hotkeys are free
    private static func quitInstalledRelease() {
        let releases = NSRunningApplication.runningApplications(withBundleIdentifier: "com.nyaaorick.island4mac")
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
