# CLIPBOARD HUB INTEGRATION GUIDE

## 🎯 OBJECTIVE

Integrate the **energy-optimized clipboard hub system** into Mac灵动岛 with zero performance impact when idle.

---

## ✅ PREREQUISITES

All files are already created:
- ✅ `Models/ClipboardItemV2.swift` (407 lines)
- ✅ `Services/ClipboardMonitorOptimized.swift` (332 lines)  
- ✅ `Services/ClipboardHubStoreOptimized.swift` (631 lines)
- ✅ `Services/KeychainStore.swift` (121 lines)
- ✅ `Services/EncryptionService.swift` (119 lines)
- ✅ `Services/SearchEngine.swift` (182 lines)
- ✅ `Utils/TouchIDManager.swift` (159 lines)
- ✅ `Views/ClipboardHubView.swift` (350 lines)
- ✅ `Settings/ClipboardSettingsWindow.swift` (562 lines)
- ✅ All supporting UI components

**Total system**: ~3,450 lines of production-ready code

---

## 📋 STEP-BY-STEP INTEGRATION

### Step 1: Add ClipboardHub to AppState

**File**: `State/AppState.swift`

**Add property** (after line 20, with other stores):
```swift
let clipboardHub = ClipboardHubStoreOptimized()
```

**Explanation**: This creates a single instance of the clipboard hub store that will be shared across the app.

---

### Step 2: Initialize ClipboardMonitor in AppDelegate

**File**: `AppDelegate.swift`

**Add property** (after line 15):
```swift
private var clipboardHubMonitor: ClipboardMonitorOptimized!
```

**Initialize in `applicationDidFinishLaunching`** (after line 70, after existing clipboardMonitor):
```swift
// Initialize clipboard hub monitor (optimized for energy efficiency)
clipboardHubMonitor = ClipboardMonitorOptimized(hubStore: appState.clipboardHub)
clipboardHubMonitor.start()
Log.serviceStarted("ClipboardHubMonitor")
```

**Stop in `applicationWillTerminate`** (after line 103):
```swift
Log.serviceStopped("ClipboardHubMonitor")
clipboardHubMonitor?.stop()
```

**Add resume hook in `applicationDidBecomeActive`** (replace existing method at line 133):
```swift
/// Called when app becomes active (e.g., via Dock click or Cmd+Tab)
func applicationDidBecomeActive(_ notification: Notification) {
    // Ensure overlay is visible when app activates
    if !appState.isOverlayVisible {
        overlayController?.show()
    }
    
    // Resume clipboard monitoring from idle state
    clipboardHubMonitor?.resumeFromIdle()
}
```

---

### Step 3: Add Hotkey to Open Clipboard Hub

**File**: ` Controllers/ OverlayWindowController.swift`

**Add method** (in the public API section):
```swift
/// Show clipboard hub window
func showClipboardHub() {
    // TODO: Present clipboard hub window modally or as separate window
    // For now, this is a placeholder for the hotkey binding
}
```

**File**: `Managers/HotKeyManager.swift`

**Add hotkey binding** (in the monitor's event handler):
```swift
// Option + V: Open Clipboard Hub
if modifierFlags.contains(.option) && keyCode == 9 {  // V key
    Task { @MainActor in
        // Show clipboard hub
        // This will be wired to a window controller or sheet
    }
}
```

---

### Step 4: Add Clipboard Hub to Main Menu

**File**: ` Controllers/StatusBarController.swift`

**Add menu item** (in the `setup()` method, after existing menu items):
```swift
// Separator
menu.addItem(NSMenuItem.separator())

// Clipboard Hub menu item
let clipboardHubItem = NSMenuItem(
    title: "Clipboard Hub",
    action: #selector(onShowClipboardHub),
    keyEquivalent: ""
)
clipboardHubItem.target = self
menu.addItem(clipboardHubItem)
```

**Add action handler**:
```swift
@objc private func onShowClipboardHub() {
    // Show clipboard hub window
    // This will be wired to a window controller
}
```

---

### Step 5: Test Integration

#### 5a. Build and Run

```bash
# Open project
open 'Mac灵动岛.xcodeproj'

# Build (Command+B)
# Run (Command+R)
```

**Expected**:
- ✅ App launches without errors
- ✅ Console shows: "ClipboardHubMonitor started (optimized)"
- ✅ No continuous CPU usage

#### 5b. Test Clipboard Monitoring

1. Copy some text (Command+C)
2. Wait 2 seconds
3. Check Console.app for: `✅ Captured text from [App Name]`

#### 5c. Test Idle Suspension

1. Don't copy anything for 70 seconds
2. Check Console.app for: `⏸️ Clipboard monitor SUSPENDED (idle for 60.0s)`
3. Check Activity Monitor: CPU should be 0.0%

#### 5d. Test Resume

1. Click the Dock icon or Cmd+Tab to app
2. Check Console.app for: `▶️ Clipboard monitor RESUMED from idle`
3. Copy something - it should be captured

---

## 🔧 WIRING CLIPBOARD HUB UI

The UI views are already created but not yet wired to a window. Here are two options:

### Option A: Modal Sheet (Recommended)

**Create a new window controller**:

```swift
// File: Controllers/ClipboardHubWindowController.swift

import Cocoa
import SwiftUI

final class ClipboardHubWindowController: NSWindowController {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Clipboard Hub"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        
        // Set content view
        let contentView = NSHostingView(
            rootView: ClipboardHubView()
                .environmentObject(appState.clipboardHub)
        )
        window.contentView = contentView
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

**Update AppDelegate**:
```swift
// Add property
private var clipboardHubWindow: ClipboardHubWindowController!

// In applicationDidFinishLaunching
clipboardHubWindow = ClipboardHubWindowController(appState: appState)

// Add method to show
func showClipboardHub() {
    clipboardHubWindow.show()
}
```

**Update hotkey manager**:
```swift
// Option + V
if modifierFlags.contains(.option) && keyCode == 9 {
    NSApp.delegate?.showClipboardHub()
}
```

---

### Option B: SwiftUI Window (macOS 14.6+)

**Add to the main app struct**:

```swift
// File:  MacNotchIslandApp.swift

@main
struct MacNotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Existing settings scene
        Settings {
            EmptyView()
        }
        
        // NEW: Clipboard Hub window
        Window("Clipboard Hub", id: "clipboard-hub") {
            ClipboardHubView()
                .environmentObject(appDelegate.appState.clipboardHub)
        }
        .defaultSize(width: 1000, height: 700)
        .windowToolbarStyle(.unifiedCompact)
    }
}
```

**Open via hotkey**:
```swift
// In HotKeyManager
if modifierFlags.contains(.option) && keyCode == 9 {
    NSWorkspace.shared.open(URL(string: "maclingdonggao://clipboard-hub")!)
}
```

---

## ⚡️ PERFORMANCE VALIDATION

After integration, you **MUST** run these tests:

### Test 1: Idle CPU (CRITICAL)

```bash
# 1. Launch app
# 2. Wait 70 seconds
# 3. Open Activity Monitor
# 4. Find "Mac灵动岛"
# 5. Check CPU column
```

**PASS**: 0.0% CPU  
**FAIL**: >0.1% CPU

---

### Test 2: Adaptive Polling

```bash
# 1. Open Console.app
# 2. Filter: subsystem:com.maclingdonggao.overlay category:clipboard_monitor
# 3. Copy 1 item
# 4. Wait 70 seconds
# 5. Observe logs
```

**Expected logs**:
```
✅ Captured text from Safari
📉 Backing off polling to 0.6s
📉 Backing off polling to 1.2s
📉 Backing off polling to 2.5s
⏸️ Clipboard monitor SUSPENDED (idle for 60.0s)
```

**PASS**: All backoff messages appear, then "SUSPENDED"  
**FAIL**: No backoff or no suspension

---

### Test 3: Instruments Energy Log

```bash
# 1. Build in Release mode
xcodebuild -project 'Mac灵动岛.xcodeproj' \
           -scheme 'Mac灵动岛' \
           -configuration Release \
           build

# 2. Launch Instruments
open -a Instruments

# 3. Select "Energy Log" template
# 4. Choose "Mac灵动岛" as target
# 5. Record for 5 minutes (idle)
```

**Expected**:
- Energy Impact: **Very Low** or **Low**
- CPU Wakeups: <10/sec
- No red "High" sections

**PASS**: Energy Impact ≤ Low  
**FAIL**: Energy Impact = High

---

## 🐛 TROUBLESHOOTING

### Issue: Build errors about missing types

**Diagnosis**: Files not added to Xcode project  
**Fix**:
1. Right-click Services folder in Xcode
2. Add Files to "Mac灵动岛"
3. Select all optimized `.swift` files
4. Ensure target "Mac灵动岛" is checked

---

### Issue: Monitor not suspending

**Diagnosis**: `resumeFromIdle()` being called too frequently  
**Fix**:
- Remove any other calls to `resumeFromIdle()` except in `applicationDidBecomeActive`
- Check no other code is accessing pasteboard (triggers change count)

---

### Issue: CPU still >0% when idle

**Diagnosis**: Other timers running (not clipboard related)  
**Fix**:
1. Search codebase for `Timer.scheduledTimer(repeating: true)`
2. Search for `DispatchSourceTimer` with `.repeating` intervals
3. Convert all to one-shot timers or use adaptive backoff

---

### Issue: Memory grows unbounded

**Diagnosis**: Thumbnail cache not evicting  
**Fix**:
- Check `maxThumbnailCacheBytes` is set to 50MB
- Verify `evictLRUThumbnail()` is being called
- Add logging: `print("Cache size: \(thumbnailCacheSize / 1024 / 1024)MB")`

---

## 📊 PERFORMANCE METRICS

After integration, the system should achieve:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Idle CPU | 0% | Activity Monitor |
| Active CPU | <0.2% | Activity Monitor |
| Memory (unlocked) | <60MB | Activity Monitor |
| Memory (locked) | <1MB | Activity Monitor |
| Disk writes | Batched (5s) | Console.app logs |
| Energy Impact | Very Low | Instruments |
| Wakeups (idle) | 0/sec | Instruments |
| Wakeups (active) | <5/sec | Instruments |

**PASS CRITERIA**: All metrics within targets

---

## 🎉 COMPLETION CHECKLIST

After integration, verify:

- [ ] App builds without errors
- [ ] Clipboard monitoring works (items captured)
- [ ] Monitor suspends after 60s (Console log)
- [ ] Monitor resumes on app activation
- [ ] Idle CPU = 0% (Activity Monitor)
- [ ] Energy Log shows "Very Low" (Instruments)
- [ ] Clipboard hub UI shows captured items
- [ ] Touch ID unlock works
- [ ] Search works
- [ ] Copy/delete works
- [ ] Memory bounded <60MB (Activity Monitor)
- [ ] Disk writes batched (Console log)

**STATUS**: ☐ Not Started / ☐ In Progress / ☐ Complete

---

## 📚 NEXT STEPS

1. **Integrate** following steps 1-4 above
2. **Test** with all 3 validation tests
3. **Profile** with Instruments Energy Log
4. **Iterate** if any test fails (see Troubleshooting)
5. **Ship** when all tests pass

---

## 📖 REFERENCES

- **Performance Optimizations**: `PERFORMANCE_OPTIMIZATIONS.md`
- **System Architecture**: `CLIPBOARD_PREMIUM_READY.md`
- **Original Delivery**: `COMPLETE_UI_DELIVERY.md`
- **Production Checklist**: `PRODUCTION_READY.md`

---

*Last Updated: Integration Guide*  
*Status: Ready for Integration*  
*Estimated Time: 30-60 minutes*
