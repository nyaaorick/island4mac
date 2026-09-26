import Cocoa
import OSLog

/// Hotkeys for the island:
/// ⇧⌘Space  open or close the island
/// ⌥⌘Space  close the island, or show it when it's hidden
/// ⌥⌘V      open the island on the clipboard tab
///
/// Note: Global event monitoring requires Accessibility permission.
/// The app will prompt users to enable it in System Settings.
final class HotKeyManager {

    /// What a hotkey does
    enum Hotkey: Equatable {
        case toggle
        case forceClose
        case clipboard
    }

    private let appState: AppState
    private let overlayController: OverlayWindowController
    private let logger = os.Logger(subsystem: Log.subsystem, category: "HotKeyManager")

    /// Keys typed in other apps
    private var globalMonitor: Any?
    /// Keys typed in this app, which the global monitor never sees: after a click on the island, or in Settings
    private var localMonitor: Any?

    /// Flag to track if we've prompted for accessibility this session
    private var hasCheckedAccessibility = false

    init(appState: AppState, overlayController: OverlayWindowController) {
        self.appState = appState
        self.overlayController = overlayController
    }

    func start() {
        stop()
        
        // Check accessibility permission before registering global monitors
        checkAccessibilityPermission()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // A hotkey doesn't go on to the island or Settings
            self?.handle(event) == true ? nil : event
        }

        logger.info("HotKey monitors registered")
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        logger.info("HotKey monitors stopped")
    }

    /// The hotkey a key press is. The modifiers have to match exactly, so ⇧⌥⌘V (Paste and Match Style in many apps)
    /// isn't taken for ⌥⌘V; Caps Lock doesn't count
    static func hotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Hotkey? {
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        switch keyCode {
        case 49 where modifiers == [.command, .shift]: return .toggle        // Space
        case 49 where modifiers == [.command, .option]: return .forceClose
        case 9 where modifiers == [.command, .option]: return .clipboard     // V
        default: return nil
        }
    }

    /// Runs the hotkey a key press is; false when it isn't one
    private func handle(_ event: NSEvent) -> Bool {
        guard !event.isARepeat, let hotkey = Self.hotkey(keyCode: event.keyCode, modifiers: event.modifierFlags) else {
            return false
        }
        switch hotkey {
        case .toggle: handlePrimaryHotkey()
        case .forceClose: handleSecondaryHotkey()
        case .clipboard: handleClipboardHotkey()
        }
        return true
    }

    // MARK: - Accessibility Permission
    
    private func checkAccessibilityPermission() {
        let isTrusted = AXIsProcessTrusted()
        logger.info("Accessibility permission: \(isTrusted ? "granted" : "not granted")")
        
        if isTrusted {
            registerAllMonitors()
        } else {
            // Prompt user on first check only
            if !hasCheckedAccessibility {
                hasCheckedAccessibility = true
                logger.warning("Global hotkeys disabled - Accessibility permission not granted")
                
                // Trigger system accessibility prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                }
            }
            
            // Still try to register - will fail silently if not trusted
            registerAllMonitors()
        }
    }
    
    private func registerAllMonitors() {
        // Monitors already registered in start()
    }

    private func handlePrimaryHotkey() {
        // ✅ MainActor 隔离修复
        Task { @MainActor in
            // Primary hotkey behavior: toggle between idle and active
            switch self.appState.interactionState {
            case .idle, .armed:
                self.appState.activateOverlay(reason: .hotkey)
            case .active, .pinned:
                self.appState.deactivateOverlay()
            }
        }
    }

    private func handleSecondaryHotkey() {
        // ✅ MainActor 隔离修复
        Task { @MainActor in
            // Secondary hotkey behavior: toggle visibility completely
            if self.appState.isOverlayVisible {
                self.appState.forceCloseOverlay()
            } else {
                self.appState.showOverlay(reason: .hotkey)
            }
        }
    }
    
    private func handleClipboardHotkey() {
        // ✅ MainActor 隔离修复
        Task { @MainActor in
            // Clipboard hotkey: open the island on the clipboard tab
            self.appState.currentSection = .clipboard
            self.appState.activateOverlay(reason: .clipboardHistory)
            self.overlayController.show()
        }
    }
}

