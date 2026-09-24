import Cocoa
import SwiftUI
import os
import UserNotifications

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
            overlayController: overlayController,
            timerManager: integration.timerManager
        )
        LOG("✅ StatusBarController initialized")
        
        // 4. Start Integration
        LOG("🟢 Starting App Integration...")
        integration.start()
        
        // 5. Special initialization for managers that need AppState/Overlay references
        setupLegacyManagers()
        
        // 6. Global Drag Monitoring is now handled by DragDetectorManager in AppState
        // (已移除重复的 GlobalDragDetector 以提升性能)
        
        LOG("══════════════════════════════════════════════════")
        LOG("✅ applicationDidFinishLaunching COMPLETED")
        LOG("══════════════════════════════════════════════════")
        LOG("")
    }
    
    private func setupLegacyManagers() {
        // Some managers might still need manual start or specific references
        // though AppIntegration should ideally handle them all.
        
        // Shelf system start
        LOG("✅ Legacy/Special managers setup complete")
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

/// Master integration coordinator for all app components
class AppIntegration {
    static let shared = AppIntegration()
    
    // MARK: - Managers
    private(set) var musicManager: MusicPlayerManager!
    private(set) var batteryManager: BatteryActivityManager!
    private(set) var calendarManager: CalendarManager!
    private(set) var timerManager: TimerManager!
    private var clipboardManager: ClipboardManager?
    private var hotKeyManager: HotKeyManager?
    private(set) var dragDropManager: InteractiveDragDropManager!
    
    // MARK: - UI Coordinators
    private(set) var animationCoordinator: AnimationCoordinator!
    private(set) var stateManager: StateTransitionManager!
    private(set) var gestureHandler: GestureHandler!
    
    // MARK: - Services
    private(set) var shelfService: ShelfPersistenceService!
    private(set) var thumbnailService: ThumbnailGenerationService!
    private(set) var quickLookService: QuickLookService!
    
    private init() {}
    
    // MARK: - Initialization
    
    func initialize() {
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("Initializing app integration...")
        
        // Initialize managers
        initializeManagers()
        
        // Initialize UI coordinators
        initializeUICoordinators()
        
        // Initialize services
        initializeServices()
        
        // Setup integrations
        setupIntegrations()
        
        logger.info("App integration complete")
    }
    
    private func initializeManagers() {
        let appState = MainActor.assumeIsolated { // ✅ MainActor 隔离修复
            OverlayWindowController.shared.getAppState()
        }
        
        musicManager = MusicPlayerManager.shared
        batteryManager = BatteryActivityManager.shared
        calendarManager = CalendarManager.shared
        
        // Set shared instances for legacy access
        Task { @MainActor in
            TimerManager.configure(appState: appState)
        }

        timerManager = TimerManager.shared
        
        dragDropManager = InteractiveDragDropManager.shared
    }
    
    private func initializeUICoordinators() {
        animationCoordinator = AnimationCoordinator.shared
        stateManager = StateTransitionManager.shared
        gestureHandler = GestureHandler.shared
        
        // Setup state transitions
        stateManager.setupNotchTransitions()
    }
    
    private func initializeServices() {
        shelfService = ShelfPersistenceService.shared
        thumbnailService = ThumbnailGenerationService.shared
        quickLookService = QuickLookService.shared
    }
    
    private func setupIntegrations() {
        // Setup analytics
        if FeatureFlags.shared.isEnabled(.experimentalFeatures) {
            AnalyticsManager.shared.startSession()
        }
        
        // Setup crash reporting
        if BuildConfig.enableCrashReporting {
            CrashReporter.shared.setup()
        }
        
        // Setup keyboard shortcuts
        setupKeyboardShortcuts()
        
        // Setup notifications
        setupNotifications()
        
        // Setup memory management
        MemoryManager.shared.logMemoryUsage()
    }
    
    private func setupKeyboardShortcuts() {
        KeyboardShortcutsManager.shared.register(
            .toggleNotch,
            identifier: "toggle_notch"
        ) {
            // Toggle notch action
        }
        
        KeyboardShortcutsManager.shared.register(
            .openSettings,
            identifier: "open_settings"
        ) {
            // Open settings action
        }
    }
    
    private func setupNotifications() {
        NotificationHelper.shared.registerNotificationCategories()
        
        // ✅ 先检查当前权限状态，避免不必要的请求
        NotificationHelper.shared.checkAuthorizationStatus { status in
            let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
            
            switch status {
            case .authorized:
                logger.info("✅ 通知权限已授予")
            case .denied:
                logger.debug("⚠️ 通知权限被拒绝（用户需要时可在设置中开启）")
            case .notDetermined:
                // 只在未决定时才请求，且静默处理，不弹窗
                logger.debug("🔔 通知权限未设置，等待用户需要时再请求")
            case .provisional:
                logger.debug("🔔 通知权限为临时状态")
            @unknown default:
                logger.debug("⚠️ 未知通知权限状态")
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func start() {
        let appState = MainActor.assumeIsolated { // ✅ MainActor 隔离修复
            OverlayWindowController.shared.getAppState()
        }

        // Start managers - wrap MusicPlayerManager (which is @MainActor) in Task
        Task { @MainActor in
            musicManager.start()
        }
        batteryManager.start()
        calendarManager.start()
        
        // Initialize and start legacy managers
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
        // Stop managers - wrap MusicPlayerManager (which is @MainActor) in Task
        Task { @MainActor in
            musicManager.stop()
        }
        batteryManager.stop()
        clipboardManager?.stop()
        hotKeyManager?.stop()
        
        // End analytics session
        AnalyticsManager.shared.endSession()
        
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("All managers stopped")
    }
    
    // MARK: - Memory Management
    
    func performMemoryCleanup() {
        MemoryManager.shared.clearCaches()
        SandboxHelper.shared.cleanTemporaryFiles()
        TaskQueue.shared.cancelAllTasks()
        
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AppIntegration")
        logger.info("Memory cleanup performed")
    }
}
