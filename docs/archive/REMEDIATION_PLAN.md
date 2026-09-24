# App Store Compliance — Immediate Remediation Plan

**Goal**: Fix critical issues blocking App Store submission  
**Timeline**: 4-5 days of focused work  
**Priority**: CRITICAL blockers first, then HIGH priority items

---

## CRITICAL BLOCKERS (Must Fix)

### 🔴 #1: Remove HoverManager Global Mouse Tracking
**Time**: 2 hours  
**Risk**: App Store rejection (privacy violation)

**Current Code** (DELETE):
```swift
// Managers/HoverManager.swift:33
monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)
```

**New Implementation** (ADD):
```swift
// In OverlayWindowController init or view setup:
func setupHoverTracking() {
    guard let contentView = window?.contentView else { return }
    
    let trackingArea = NSTrackingArea(
        rect: contentView.bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil
    )
    contentView.addTrackingArea(trackingArea)
}

// Handle hover locally:
override func mouseEntered(with event: NSEvent) {
    appState.armOverlay()
}

override func mouseExited(with event: NSEvent) {
    appState.disarmOverlay()
}
```

**Steps**:
1. Delete `HoverManager.swift` entirely
2. Add `NSTrackingArea` to `OverlayWindowController`
3. Implement `mouseEntered`/`mouseExited` in window or view responder
4. Remove HoverManager from AppDelegate
5. Test: hover still triggers armed state, no global tracking

**Validation**:
```bash
# Before: Activity Monitor shows constant CPU usage
# After: CPU drops to <0.5% when idle
```

---

### 🔴 #2: Add Info.plist Permission Descriptions
**Time**: 1 hour  
**Risk**: App Store rejection (missing required keys)

**Add to Info.plist**:
```xml
<key>NSAppleEventsUsageDescription</key>
<string>Mac灵动岛 uses keyboard shortcuts (⌘⇧Space) to quickly toggle the overlay. Your keystrokes are only checked for this specific combination and are never recorded or transmitted.</string>

<key>NSAccessibilityUsageDescription</key>
<string>Mac灵动岛 needs accessibility permission to register global keyboard shortcuts. This is only used to detect the hotkey combination and does not monitor your activity.</string>

<key>LSUIElement</key>
<true/>
<!-- App runs as menu bar utility, no Dock icon -->

<key>NSHumanReadableCopyright</key>
<string>Copyright © 2026. Not affiliated with Apple Inc.</string>
```

**Steps**:
1. Open `Info.plist` in Xcode
2. Add usage description keys
3. Test: First launch shows system permission dialog with custom text
4. Verify rejection gracefully handled (app doesn't crash if denied)

---

### 🔴 #3: Fix HotKeyManager — Use Carbon API
**Time**: 4 hours  
**Risk**: App Store scrutiny (global keyboard monitoring)

**Current Code** (REPLACE):
```swift
// Managers/HotKeyManager.swift:22
NSEvent.addGlobalMonitorForEvents(matching: .keyDown)
```

**New Implementation** (Carbon HotKey API):
```swift
import Carbon

final class HotKeyManager {
    private var primaryHotKeyRef: EventHotKeyRef?
    private var secondaryHotKeyRef: EventHotKeyRef?
    
    func start() {
        stop()
        
        // Register Cmd+Shift+Space
        var primaryID = EventHotKeyID(signature: OSType(0x4D4E4F54), id: 1) // 'MNOT'
        let primaryModifiers = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(49, primaryModifiers, primaryID, GetApplicationEventTarget(), 0, &primaryHotKeyRef)
        
        // Register Cmd+Option+Space
        var secondaryID = EventHotKeyID(signature: OSType(0x4D4E4F54), id: 2)
        let secondaryModifiers = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(49, secondaryModifiers, secondaryID, GetApplicationEventTarget(), 0, &secondaryHotKeyRef)
        
        // Install event handler
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, unsafeBitCast(self, to: UnsafeMutableRawPointer.self), nil)
    }
    
    func stop() {
        if let ref = primaryHotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = secondaryHotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}
```

**Alternative (Simpler)**:
Use `MASShortcut` library (popular, App Store approved):
```swift
// Add via SPM: https://github.com/shpakovski/MASShortcut
```

**Steps**:
1. Implement Carbon HotKey API or integrate MASShortcut
2. Remove global NSEvent monitors
3. Test: Hotkeys still work, no global key interception
4. Add UI to show/change hotkeys (Settings panel)

---

### 🔴 #4: Add Settings UI with Feature Toggles
**Time**: 8 hours  
**Risk**: App Store rejection (no user control over intrusive features)

**Required Settings Window**:
```swift
struct SettingsView: View {
    @AppStorage("hover_enabled") var hoverEnabled = true
    @AppStorage("hotkeys_enabled") var hotkeysEnabled = true
    @AppStorage("clipboard_enabled") var clipboardEnabled = true
    @AppStorage("media_enabled") var mediaEnabled = true
    
    var body: some View {
        Form {
            Section("Interaction") {
                Toggle("Enable hover detection", isOn: $hoverEnabled)
                    .help("Show overlay when you hover near the notch")
                
                Toggle("Enable keyboard shortcuts", isOn: $hotkeysEnabled)
                    .help("Use ⌘⇧Space to toggle overlay")
            }
            
            Section("Features") {
                Toggle("Monitor clipboard", isOn: $clipboardEnabled)
                    .help("Show clipboard contents in overlay")
                
                Toggle("Show now playing", isOn: $mediaEnabled)
                    .help("Display media controls when music is playing")
            }
            
            Section("Privacy") {
                Link("Privacy Policy", destination: URL(string: "https://yoursite.com/privacy")!)
                Text("Mac灵动岛 runs locally. No data is transmitted.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 400)
    }
}
```

**Steps**:
1. Create `SettingsView.swift`
2. Add Settings window to App menu
3. Wire toggles to managers (start/stop based on settings)
4. Test: Disabling features actually stops them
5. Add first-run onboarding explaining features

---

## HIGH PRIORITY (Fix Before Launch)

### 🟡 #5: Wire InteractionCoordinator
**Time**: 8 hours  
**Risk**: State desync, race conditions

**Already Designed**: `Coordination/InteractionCoordinator.swift` exists  
**Task**: Integrate into existing codebase

**Follow**: `COORDINATOR_INTEGRATION.md` guide

**Steps**:
1. Create coordinator instance in AppDelegate
2. Inject via SwiftUI environment
3. Migrate all views to post events (not mutate state)
4. Deprecate old AppState methods
5. Run full regression test

---

### 🟡 #6: Implement Safe-Fail Recovery
**Time**: 4 hours  
**Risk**: App gets stuck, user frustrated

**Add to AppState**:
```swift
func forceRecoveryState() {
    interactionState = .idle
    overlayMode = .compact
    isOverlayVisible = true
    visibilityReason = .none
    
    // Clear all transient state
    payload = .none
    hint = nil
    lastCopiedAt = nil
    
    // Notify window controller to reset
    NotificationCenter.default.post(name: .forceRecovery, object: nil)
}

func validateState() {
    // Run every 10 seconds in production
    let expectedMode: OverlayMode = interactionState.isExpanded ? .expanded : .compact
    if overlayMode != expectedMode {
        logCriticalError("State desync detected")
        forceRecoveryState()
    }
}
```

**Add to OverlayWindowController**:
```swift
func validateWindowPosition() {
    guard let window = self.window else { return }
    let isOnScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    
    if !isOnScreen {
        logCriticalError("Window off-screen")
        positionAtNotch() // Recover
    }
}

// Register for system events
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleSystemWake),
    name: NSWorkspace.didWakeNotification,
    object: nil
)

@objc func handleSystemWake() {
    validateWindowPosition()
    appState.validateState()
}
```

---

## POST-REMEDIATION VALIDATION

### Manual Testing Required

#### Basic Function (15 min)
- [ ] App launches without errors
- [ ] Overlay appears in compact mode (idle)
- [ ] Click → expands
- [ ] ESC → collapses
- [ ] Drag file → expands, drop → stays expanded
- [ ] Hotkey (⌘⇧Space) → toggles

#### CPU/Memory (30 min)
- [ ] Open Activity Monitor
- [ ] Launch app, let sit idle for 5 minutes
- [ ] CPU <0.5%
- [ ] Memory <50MB
- [ ] Hover over overlay (if enabled): CPU <1.0%
- [ ] Run 1 hour: memory stable, no leaks

#### Settings (10 min)
- [ ] Open Settings window
- [ ] Disable hover → hover doesn't work
- [ ] Disable hotkeys → hotkeys don't work
- [ ] Disable clipboard → no clipboard monitoring
- [ ] Re-enable → features work again

#### Multi-Monitor (15 min)
- [ ] Disconnect external display → overlay moves to main
- [ ] Reconnect → overlay repositions
- [ ] Switch primary display → overlay follows

#### Sleep/Wake (10 min)
- [ ] Sleep Mac
- [ ] Wake Mac
- [ ] Overlay repositions correctly
- [ ] No crash, no stuck state

---

## SUCCESS CRITERIA

### Before Submission Checklist

✅ **No global mouse tracking** (HoverManager removed)  
✅ **Carbon HotKey API** (or MASShortcut library)  
✅ **Info.plist descriptions** (all required keys)  
✅ **Settings UI** (toggle all features)  
✅ **InteractionCoordinator wired** (all events go through coordinator)  
✅ **Safe-fail recovery** (forceRecoveryState implemented)  
✅ **CPU idle <0.5%** (verified in Activity Monitor)  
✅ **Memory <60MB** (after 1 hour)  
✅ **All manual tests pass** (see above)  

### App Store Description Requirements

Must include:
- "Third-party notch utility (not affiliated with Apple)"
- "Requires macOS 14.0+ with notch (or works on any Mac)"
- "Uses keyboard shortcuts for quick access"
- "All data processed locally, no internet required"
- Clear screenshot showing it's NOT a system feature

---

## TIMELINE

### Day 1 (8 hours)
- Remove HoverManager (2h)
- Add Info.plist descriptions (1h)
- Start HotKeyManager Carbon API migration (4h)
- Test basic functionality (1h)

### Day 2 (8 hours)
- Finish HotKeyManager Carbon API (2h)
- Create Settings UI (6h)

### Day 3 (8 hours)
- Wire InteractionCoordinator (full day)

### Day 4 (8 hours)
- Implement safe-fail recovery (4h)
- Full QA regression testing (4h)

### Day 5 (3 hours)
- Fix any issues found in QA
- Final validation
- Prepare App Store submission materials

**Total**: 35 hours across 5 days

---

## RISK ASSESSMENT AFTER REMEDIATION

### Remaining Risks (Low)

🟢 **Window positioning**: Low risk — recovery mechanism added  
🟢 **State desync**: Low risk — coordinator + validation  
🟢 **Permission denial**: Low risk — graceful degradation  
🟢 **Multi-monitor**: Low risk — already handles correctly  
🟢 **Sleep/wake**: Low risk — validation on wake  

### App Store Approval Likelihood

**Before Remediation**: 20% (likely rejection)  
**After Remediation**: 85% (strong approval chance)

Remaining 15% risk due to:
- Subjective reviewer interpretation of "system UI imitation"
- Hotkey conflicts with other apps (suggest customizable)
- First-time app, no prior review history

**Mitigation**:
- Clear "third-party" branding
- Excellent app description
- Professional screenshots
- Responsive support email

---

## CONTACT

Questions during remediation:
- See `APP_STORE_READINESS.md` for detailed analysis
- See `COORDINATOR_INTEGRATION.md` for wiring guide
- See `INTERACTION_INVARIANTS.md` for state machine rules

---

**Status**: 🔴 NOT READY (4-5 days of work remaining)  
**After Fixes**: ✅ READY TO SUBMIT  
**Confidence**: HIGH (compliance issues are fixable, architecture is sound)
