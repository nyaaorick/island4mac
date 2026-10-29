import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let integration = AppIntegration.shared
    /// Strong references: the island and the menu bar item live as long as the app
    private(set) var islandController: IslandController!
    private(set) var statusBarController: StatusBarController!

    nonisolated var appState: AppState {
        MainActor.assumeIsolated { islandController.getAppState() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app: no monitors, hotkeys or menu bar item while they run
        guard !BuildConfig.isRunningUnitTests else { return }
        // Menu bar only, no Dock icon
        NSApp.setActivationPolicy(.accessory)
        islandController = IslandController.shared
        statusBarController = StatusBarController(appState: appState, islandController: islandController)
        integration.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        integration.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
