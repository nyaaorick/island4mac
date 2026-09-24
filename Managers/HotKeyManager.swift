import Cocoa
import OSLog

/// Global hotkeys for overlay control.
/// Primary:   Cmd + Shift + Space  (toggle overlay)
/// Secondary: Cmd + Option + Space  (force close)
/// Clipboard: Cmd + Option + V      (open clipboard tab)
/// Lock:      Cmd + Option + L      (toggle position lock)
/// Move Mode: Cmd + Option + M      (toggle free move mode)
///
/// Note: Global event monitoring requires Accessibility permission.
/// The app will prompt users to enable it in System Settings.
final class HotKeyManager {

    private let appState: AppState
    private let overlayController: OverlayWindowController
    private let logger = os.Logger(subsystem: Log.subsystem, category: "HotKeyManager")

    private var primaryMonitor: Any?
    private var secondaryMonitor: Any?
    private var clipboardMonitor: Any?
    private var lockMonitor: Any?
    private var moveModeMonitor: Any?
    
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

        // Primary hotkey: ⇧⌘Space (Shift+Command+Space)
        primaryMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }

            if event.keyCode == 49,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.shift) {
                self.handlePrimaryHotkey()
            }
        }

        // Secondary hotkey: ⌥⌘Space (Option+Command+Space)
        secondaryMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }

            if event.keyCode == 49,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option) {
                self.handleSecondaryHotkey()
            }
        }
        
        // Clipboard hotkey: ⌥⌘V (Option+Command+V, keyCode 9)
        clipboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }
            
            if event.keyCode == 9,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option) {
                self.handleClipboardHotkey()
            }
        }
        
        // Lock hotkey: ⌥⌘L (Option+Command+L, keyCode 37)
        lockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }
            
            if event.keyCode == 37,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option) {
                self.handleLockHotkey()
            }
        }
        
        // Move Mode hotkey: ⌥⌘M (Option+Command+M, keyCode 46)
        moveModeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard !event.isARepeat else { return }
            
            if event.keyCode == 46,
               event.modifierFlags.contains(.command),
               event.modifierFlags.contains(.option) {
                self.handleMoveModeHotkey()
            }
        }
        
        logger.info("HotKey monitors registered")
    }

    func stop() {
        if let primaryMonitor { NSEvent.removeMonitor(primaryMonitor) }
        if let secondaryMonitor { NSEvent.removeMonitor(secondaryMonitor) }
        if let clipboardMonitor { NSEvent.removeMonitor(clipboardMonitor) }
        if let lockMonitor { NSEvent.removeMonitor(lockMonitor) }
        if let moveModeMonitor { NSEvent.removeMonitor(moveModeMonitor) }
        primaryMonitor = nil
        secondaryMonitor = nil
        clipboardMonitor = nil
        lockMonitor = nil
        moveModeMonitor = nil
        logger.info("HotKey monitors stopped")
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
    
    private func handleLockHotkey() {
        // ✅ MainActor 隔离修复
        Task { @MainActor in
            // Toggle position lock
            self.appState.togglePositionLock()
            
            // Visual feedback: briefly show overlay
            self.overlayController.showTemporarily(duration: 1.5)
        }
    }
    
    private func handleMoveModeHotkey() {
        // ✅ MainActor 隔离修复
        Task { @MainActor in
            // Toggle move mode
            self.appState.toggleMoveMode()
            
            // Visual feedback: briefly show overlay
            self.overlayController.showTemporarily(duration: 1.5)
        }
    }
}

