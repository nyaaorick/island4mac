import Cocoa
import SwiftUI

// Import the menu bar icon creation function
// (defined in Views/MenuBarIconView.swift)

/// Controller for the status bar (menu bar) item
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    
    private var appState: AppState  // Strong reference
    private var overlayController: OverlayWindowController  // Strong reference

    // MARK: - Initialization

    init(appState: AppState, overlayController: OverlayWindowController) {
        self.appState = appState
        self.overlayController = overlayController
        
        super.init()  // REQUIRED for NSObject subclass before using self
        
        setup()
    }
    
    // MARK: - Setup
    
    func setup() {
        print("[STATUS-BAR] ========================================")
        print("[STATUS-BAR] Setting up status bar item...")
        
        // Create status bar item with fixed length for visibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard statusItem != nil else {
            print("[STATUS-BAR] FATAL: Failed to create status item!")
            return
        }
        
        // Configure button with two circles icon (一大一小)
        if let button = statusItem.button {
            // Create custom icon with two filled circles
            let icon = createTwoCirclesIcon()
            button.image = icon
            button.imagePosition = .imageOnly
            
            // Set accessibility
            button.toolTip = "Mac灵动岛"
            
            print("[STATUS-BAR] Button configured with two circles icon")
        } else {
            print("[STATUS-BAR] ERROR: No button on status item!")
        }
        
        // Create menu
        createMenu()
        
        // Assign menu to status item
        statusItem.menu = menu
        menu.delegate = self
        
        print("[STATUS-BAR] Menu assigned: \(statusItem.menu != nil)")
        print("[STATUS-BAR] Menu item count: \(menu.items.count)")
        print("[STATUS-BAR] Status item visible: \(statusItem.isVisible)")
        print("[STATUS-BAR] Setup complete!")
        print("[STATUS-BAR] ========================================")
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
        print("[STATUS-BAR] Menu will open!")
    }
    
    func menuDidClose(_ menu: NSMenu) {
        print("[STATUS-BAR] Menu closed")
    }
    
    // MARK: - Menu Creation
    
    private func createMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false
        
        // Show Overlay
        let showItem = NSMenuItem(title: "显示灵动岛", action: #selector(onShow), keyEquivalent: "s")
        showItem.target = self
        showItem.isEnabled = true
        menu.addItem(showItem)
        
        // Hide Overlay
        let hideItem = NSMenuItem(title: "隐藏灵动岛", action: #selector(onHide), keyEquivalent: "h")
        hideItem.target = self
        hideItem.isEnabled = true
        menu.addItem(hideItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(onSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Debug
        let debugMenu = NSMenu(title: "调试与开发")
        
        let centerItem = NSMenuItem(title: "居中显示 (重置位置)", action: #selector(onCenterDebugOverlay), keyEquivalent: "d")
        centerItem.target = self
        debugMenu.addItem(centerItem)
        
        let debugItem = NSMenuItem(title: "调试模式", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "退出 Mac灵动岛", action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        
        print("[STATUS-BAR] Menu created with \(menu.items.count) items")
    }

    
    // MARK: - Actions
    
    @objc func onShow() {
        print("")
        print("╔══════════════════════════════════════════════════════════╗")
        print("║ [STATUS-BAR] onShow() CLICKED                             ║")
        print("╚══════════════════════════════════════════════════════════╝")
        print("   OverlayController retained: \(Unmanaged.passUnretained(overlayController).toOpaque())")
        
        // Ensure activation policy allows windows
        let policy = NSApp.activationPolicy()
        print("   Current activation policy: \(policy.rawValue) (0=regular, 1=accessory, 2=prohibited)")
        if policy == .prohibited {
            print("⚠️ FIXING: Activation policy is .prohibited!")
            NSApp.setActivationPolicy(.accessory)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        overlayController.show()
    }
    
    @objc func onHide() {
        print("[STATUS-BAR] onHide called")
        overlayController.hide()
    }
    
    @objc func onSettings() {
        print("[STATUS-BAR] onSettings called")
        SettingsWindowController.shared.showSettings()
    }
    
    @objc func onCenterDebugOverlay() {
        print("")
        print("═══════════════════════════════════════════════════════")
        print("[STATUS-BAR] onCenterDebugOverlay called - FORCING CENTER POSITION")
        print("═══════════════════════════════════════════════════════")
        
        // Use AppState to trigger reset as we don't access window directly anymore
        appState.isPositionLocked = true
        appState.isMoveModeEnabled = false
        overlayController.reposition()
        
        // Force visibility via app state
        appState.isOverlayVisible = true
        appState.overlayMode = .compact
        
        print("[DEBUG] Triggered state reset via AppState")
        print("═══════════════════════════════════════════════════════")
        print("")
    }
    
    @objc func onQuit() {
        print("[STATUS-BAR] onQuit called")
        NSApp.terminate(nil)
    }
    
    // MARK: - Icon Creation
    
    private func createTwoCirclesIcon() -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Draw minimalist pill/capsule shape (like Dynamic Island)
        NSColor.labelColor.setFill()
        
        let pillRect = NSRect(x: 3, y: 5, width: 12, height: 6)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 3, yRadius: 3)
        pillPath.fill()
        
        image.unlockFocus()
        image.isTemplate = true  // Adapts to dark/light mode
        
        return image
    }
    
    // MARK: - Cleanup
    
    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
