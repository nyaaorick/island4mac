import Cocoa
import SwiftUI
import os

// MARK: - Debug Helper
private func LOG(_ message: String) {
    let msg = "[🍎 AppDelegate] \(message)"
    print(msg)
    NSLog("%@", msg)  // NSLog is more reliable for debugging
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components (STRONG REFERENCES - CRITICAL!)

    /// master integration coordinator
    let integration = AppIntegration.shared

    /// Island controller - manages the dynamic island windows.
    /// MUST be stored as a strong property to prevent deallocation!
    var islandController: IslandController!

    /// Status bar (menu bar) controller - STRONG reference
    var statusBarController: StatusBarController!

    // MARK: - State Access

    // ✅ MainActor isolation fix - nonisolated lets this property be called from non-MainActor contexts
    nonisolated var appState: AppState {
        MainActor.assumeIsolated {
            islandController.getAppState()
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; don't start global monitors, hotkeys
        // or the menu bar item while they run.
        guard !BuildConfig.isRunningUnitTests else { return }

        LOG("")
        LOG("══════════════════════════════════════════════════")
        LOG("🚀 applicationDidFinishLaunching STARTING")
        LOG("══════════════════════════════════════════════════")

        // Use accessory mode (no dock icon, only menu bar)
        NSApp.setActivationPolicy(.accessory)
        LOG("Set activation policy to .accessory")

        // 1. Initialize the island controller (SINGLETON - stored as strong property)
        islandController = IslandController.shared
        LOG("✅ IslandController initialized")

        // 2. Initialize App Integration
        LOG("🔧 Initializing App Integration...")
        integration.initialize()

        // 3. Initialize status bar
        statusBarController = StatusBarController(
            appState: appState,
            islandController: islandController
        )
        LOG("✅ StatusBarController initialized")

        // 4. Start Integration
        LOG("🟢 Starting App Integration...")
        integration.start()

        // Global drag monitoring is handled by DragMonitor in AppState

        LOG("══════════════════════════════════════════════════")
        LOG("✅ applicationDidFinishLaunching COMPLETED")
        LOG("══════════════════════════════════════════════════")
        LOG("")
    }

    func applicationWillTerminate(_ notification: Notification) {
        LOG("👋 [AppDelegate] applicationWillTerminate")
        integration.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

