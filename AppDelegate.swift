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

    /// Overlay window controller - manages the dynamic island window.
    /// MUST be stored as a strong property to prevent deallocation!
    var overlayController: OverlayWindowController!

    /// Status bar (menu bar) controller - STRONG reference
    var statusBarController: StatusBarController!

    // MARK: - State Access

    // ✅ MainActor 隔离修复 - nonisolated 使得该属性可以在非 MainActor 上下文中调用
    nonisolated var appState: AppState {
        MainActor.assumeIsolated {
            overlayController.getAppState()
        }
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        LOG("")
        LOG("══════════════════════════════════════════════════")
        LOG("🚀 applicationDidFinishLaunching STARTING")
        LOG("══════════════════════════════════════════════════")

        // Use accessory mode (no dock icon, only menu bar)
        NSApp.setActivationPolicy(.accessory)
        LOG("Set activation policy to .accessory")

        // 1. Initialize overlay controller (SINGLETON - stored as strong property)
        overlayController = OverlayWindowController.shared
        LOG("✅ OverlayWindowController initialized")

        // 2. Initialize App Integration
        LOG("🔧 Initializing App Integration...")
        integration.initialize()

        // 3. Initialize status bar
        statusBarController = StatusBarController(
            appState: appState,
            overlayController: overlayController
        )
        LOG("✅ StatusBarController initialized")

        // 4. Start Integration
        LOG("🟢 Starting App Integration...")
        integration.start()

        // Global drag monitoring is handled by DragDetectorManager in AppState

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

// MARK: - AppIntegration

/// Starts and stops the background managers that feed the island
class AppIntegration {
    static let shared = AppIntegration()

    // MARK: - Managers
    private var clipboardManager: ClipboardManager?
    private var hotKeyManager: HotKeyManager?

    private init() {}

    // MARK: - Initialization

    func initialize() {
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("Initializing app integration...")

        // Setup analytics
        if FeatureFlags.shared.isEnabled(.experimentalFeatures) {
            AnalyticsManager.shared.startSession()
        }

        // Setup crash reporting
        if BuildConfig.enableCrashReporting {
            CrashReporter.shared.setup()
        }

        // Setup memory management
        MemoryManager.shared.logMemoryUsage()

        logger.info("App integration complete")
    }

    // MARK: - Lifecycle

    func start() {
        let appState = MainActor.assumeIsolated { // ✅ MainActor 隔离修复
            OverlayWindowController.shared.getAppState()
        }

        // Music playback observation is wired up by OverlayWindowController
        CalendarManager.shared.start()

        clipboardManager = ClipboardManager(vault: appState.clipVault)
        clipboardManager?.start()

        Task { @MainActor in
            let ctrl = OverlayWindowController.shared
            hotKeyManager = HotKeyManager(appState: appState, overlayController: ctrl)
            hotKeyManager?.start()
        }

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers started")
    }

    func stop() {
        MusicManager.shared.stop()
        clipboardManager?.stop()
        hotKeyManager?.stop()

        // End analytics session
        AnalyticsManager.shared.endSession()

        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers stopped")
    }
}
