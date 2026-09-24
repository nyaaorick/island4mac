# App Store Readiness Assessment — v1.0 Release Candidate

**Status**: 🔴 **NOT READY** — Critical issues found  
**Assessment Date**: 2026-01-10  
**Reviewer Perspective**: macOS Engineer + QA Lead + App Store Reviewer

---

## STEP 1: APP STORE REVIEW RISK ANALYSIS

### 🚨 CRITICAL ISSUES (Must Fix Before Submission)

#### **Issue #1: HoverManager Uses Global Mouse Tracking**
**File**: `Managers/HoverManager.swift:33`
```swift
monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)
```

**Risk Level**: 🔴 **HIGH — Likely Rejection**

**Why This Is Problematic**:
- Global `.mouseMoved` monitoring is **extremely invasive**
- Fires on EVERY mouse movement system-wide (hundreds/second)
- Violates user privacy expectations
- Appears as spyware-like behavior to reviewers
- Causes measurable CPU impact (polling)
- No clear user benefit justifying global tracking

**Apple Reviewer's Question**:
> "Why does this app need to track my mouse movements everywhere on the screen?"

**Current Implementation**:
- Monitors ALL mouse movements globally
- Then checks if mouse is "near" overlay window
- This is backwards: window should detect hover via OS, not poll globally

**Recommended Fix**:
```swift
// REMOVE: Global mouse tracking
// REPLACE WITH: NSTrackingArea on overlay window

let trackingArea = NSTrackingArea(
    rect: window.bounds,
    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
    owner: self,
    userInfo: nil
)
window.contentView?.addTrackingArea(trackingArea)

// Handle in responder chain (no global monitor)
override func mouseEntered(with event: NSEvent) {
    coordinator.handle(.hoverEntered)
}

override func mouseExited(with event: NSEvent) {
    coordinator.handle(.hoverExited)
}
```

**Impact**: Eliminates global mouse tracking entirely. Hover detection becomes local, private, CPU-efficient.

---

#### **Issue #2: HotKeyManager Uses Raw Global Key Interception**
**File**: `Managers/HotKeyManager.swift:22, 33`
```swift
NSEvent.addGlobalMonitorForEvents(matching: .keyDown)
```

**Risk Level**: 🟡 **MEDIUM — May Trigger Scrutiny**

**Why This Is Concerning**:
- Global keyboard monitoring (security/privacy concern)
- Current implementation intercepts ALL keyDown events
- Then filters for specific key combos
- Could be seen as keylogging behavior

**Apple Reviewer's Question**:
> "Why does this app monitor all keyboard input globally?"

**Current Design Issues**:
- Two separate monitors for two hotkey combos (inefficient)
- No clear UI explaining why global key access is needed
- No graceful degradation if permission denied
- Hotkeys conflict with system shortcuts on some keyboards

**Recommended Fix**:
```swift
// OPTION 1: Use Carbon HotKey API (more legitimate for system utilities)
RegisterEventHotKey(49, cmdKey | shiftKey, ...)

// OPTION 2: Require user to register via System Preferences > Keyboard > Shortcuts
// (Show instructions in app, let system handle global shortcuts)

// OPTION 3: Local event monitor + require app to be key (safer)
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    // Only works when app is active (safer, no global interception)
}
```

**Impact**: More legitimate hotkey handling. Clearer user consent model.

---

#### **Issue #3: Window Behavior Might Appear to "Spoof" System UI**
**File**: `OverlayWindowController.swift:57`
```swift
window.level = .statusBar
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

**Risk Level**: 🟡 **MEDIUM — Needs Justification**

**Why This Could Be Flagged**:
- Window appears at same level as macOS status bar
- Sits at top-center (where macOS notch/camera indicator appears)
- Could be perceived as imitating system UI
- Reviewer might think it's trying to deceive users

**Apple Reviewer's Question**:
> "Is this app trying to imitate macOS system UI elements?"

**Current Mitigation** (Good):
- Uses `.nonactivatingPanel` (doesn't steal focus)
- Clear app-specific branding (not mimicking system icons)
- Transparent about being a third-party utility

**Additional Safeguards Needed**:
1. **Visual Differentiation**:
   - Ensure UI looks distinctly third-party (not Apple-designed)
   - Add subtle app branding/identity
   - Use non-system colors for primary UI

2. **Documentation for Review**:
   - App Store description MUST clearly state: "Third-party notch utility"
   - Screenshots must show it's NOT a system feature
   - Include disclaimer: "Not affiliated with Apple"

3. **Behavior Limits**:
   - NEVER show system-style alerts or warnings from overlay
   - NEVER display system icon lookalikes (battery, WiFi, etc.)
   - NEVER intercept clicks meant for real status bar

---

### ⚠️ MODERATE CONCERNS (Address Before Launch)

#### **Concern #1: No Permission Explanations**
**Current State**:
- App uses global event monitors (keyboard, mouse) without explanation
- No Info.plist usage descriptions
- No first-run permission request UI

**Required**:
```xml
<!-- Info.plist -->
<key>NSAppleEventsUsageDescription</key>
<string>Mac灵动岛 uses keyboard shortcuts to quickly show the overlay. Your keystrokes are only checked for hotkey combinations and are never recorded or transmitted.</string>

<key>NSAccessibilityUsageDescription</key>
<string>Mac灵动岛 needs accessibility access to detect when you hover near the notch overlay. This is only used to show/hide the overlay and does not track your activity.</string>
```

**Required UI**:
- First-run onboarding explaining permissions
- Clear opt-out for global monitors (HoverManager especially)
- Link to privacy policy (even if simple)

---

#### **Concern #2: Safe Mode is Ad-Hoc**
**File**: `AppDelegate.swift:42`
```swift
if !UserDefaults.standard.bool(forKey: "safe_mode_enabled") {
    hoverManager.start()
}
```

**Issues**:
- Safe mode exists but isn't user-facing
- No UI to toggle safe mode
- User can't disable intrusive features without editing UserDefaults
- Reviewer might see HoverManager as "always on" invasive feature

**Required**:
- Settings UI with "Disable hover detection" toggle
- Clear explanation: "Disables global mouse tracking for privacy"
- Safe mode should disable ALL global monitors, not just hover

---

### ✅ POSITIVE ASPECTS (Good for Review)

#### **Good #1: Non-Activating Panel**
```swift
styleMask: [.borderless, .nonactivatingPanel]
window.hidesOnDeactivate = false
```
✅ Respects macOS conventions  
✅ Doesn't steal focus  
✅ Behaves like legitimate system utility  

#### **Good #2: Clean Shutdown**
```swift
func applicationWillTerminate(_ notification: Notification) {
    hotKeyManager?.stop()
    hoverManager?.stop()
    clipboardManager?.stop()
    // All monitors removed
}
```
✅ No zombie monitors  
✅ Clean resource cleanup  
✅ No background processes after quit  

#### **Good #3: No Private APIs**
✅ All AppKit/Cocoa public APIs  
✅ No runtime injection  
✅ No undocumented SPI calls  

---

## STEP 2: USER EXPECTATION ALIGNMENT

### Stress Test: User Doesn't Read Instructions

#### **Scenario 1: User Drags File, Changes Mind**
**Expected**: Overlay expands, user drags away, overlay collapses  
**Current**: ✅ Works (dragExited handled)  
**Risk**: 🟢 None

#### **Scenario 2: User Clicks Rapidly (10 clicks/sec)**
**Expected**: State machine handles gracefully  
**Current**: ⚠️ Unknown — no reentrant safety yet (coordinator not wired)  
**Risk**: 🟡 **State could desync without coordinator**

**Required**: Wire `InteractionCoordinator` before v1.0

#### **Scenario 3: User Hovers, Immediately Clicks**
**Expected**: Click wins, overlay activates  
**Current**: ⚠️ HoverManager might expand, then click tries to activate  
**Risk**: 🟡 **Race condition between hover expansion and click activation**

**Fix**: Hover detection must go through coordinator (single event queue)

#### **Scenario 4: User Has Multiple Monitors**
**Expected**: Overlay appears on active monitor only  
**Current**: ✅ Uses `ScreenManager.activeScreen(displayMode: .activeOnly)`  
**Risk**: 🟢 None

#### **Scenario 5: User Enables Full-Screen App**
**Expected**: Overlay still visible (`.fullScreenAuxiliary`)  
**Current**: ✅ Window collection behavior correct  
**Risk**: 🟢 None

#### **Scenario 6: User Leaves App Running All Day**
**Expected**: No CPU spike, no memory leak  
**Current**: 🔴 **HoverManager polls mouse movements continuously**  
**Risk**: 🔴 **HIGH — CPU usage unacceptable**

**Measurement Needed**:
```
Idle (overlay hidden): <0.1% CPU
Idle (overlay visible): <0.5% CPU
Hover monitoring: <1.0% CPU (currently likely 3-5%)
Memory after 24hr: <60MB
```

---

### The Overlay Must NEVER:

❌ **Block core workflows**  
✅ Current: Non-activating panel, doesn't block input to other apps  

❌ **Trap input**  
⚠️ Current: Global mouse/keyboard monitors could appear to "trap" input  
🔧 Fix: Remove global monitors, use local tracking only  

❌ **Steal focus unexpectedly**  
✅ Current: `.nonactivatingPanel` prevents this  

❌ **Fail to recover to safe state**  
⚠️ Current: No explicit recovery mechanism  
🔧 Fix: Add safe-fail design (see Step 3)  

---

## STEP 3: SAFE-FAIL DESIGN

### Failure Recovery Contract

**Rule**: On ANY detected anomaly, app MUST return to:
```
State: idle
Mode: compact
Visible: true
Interactive: false
Alpha: 1.0
Monitors: removed
```

This is the **recovery state** — visible but inert.

---

### Failure Case Matrix

#### **Case 1: State Desync Detected**
**Trigger**: `overlayMode != interactionState.isExpanded`  
**Current**: Assertion in coordinator (debug only)  
**Production Behavior Needed**:
```swift
func detectStateDesync() {
    let expectedMode: OverlayMode = interactionState.isExpanded ? .expanded : .compact
    
    if overlayMode != expectedMode {
        // Log to crash reporter / telemetry
        logCriticalError("State desync: mode=\(overlayMode), expected=\(expectedMode)")
        
        // Force safe state
        forceRecoveryState()
    }
}

func forceRecoveryState() {
    interactionState = .idle
    overlayMode = .compact
    isOverlayVisible = true
    removeAllEventMonitors()
    cancelAllTimers()
    
    // Show transient notification (optional)
    showRecoveryNotice() // "Overlay reset due to internal error"
}
```

---

#### **Case 2: Window Position Invalid**
**Trigger**: Window frame outside all screen bounds  
**Current**: No validation  
**Production Behavior Needed**:
```swift
func validateWindowPosition() {
    guard let window = self.window else { return }
    let frame = window.frame
    
    // Check if window is visible on ANY screen
    let isOnScreen = NSScreen.screens.contains { screen in
        screen.frame.intersects(frame)
    }
    
    if !isOnScreen {
        logCriticalError("Window off-screen: \(frame)")
        
        // Reposition to main screen notch
        if let mainScreen = NSScreen.main {
            positionAtNotch(screen: mainScreen)
        } else {
            // Catastrophic: no screens available
            forceRecoveryState()
        }
    }
}
```

**When to Check**:
- After screen configuration change
- After sleep/wake
- After display disconnect/reconnect
- On app relaunch

---

#### **Case 3: Drag Session Cancelled Mid-Way**
**Trigger**: `dragExited` without `dropCompleted`  
**Current**: ✅ Handled — collapses if reason was `.dragHover`  
**Additional Safety**:
```swift
// Timeout: if dragEntered but no exit/drop within 30 seconds
private var dragTimeoutTimer: DispatchWorkItem?

func handleDragEntered() {
    coordinator.handle(.dragEntered)
    
    // Safety timeout
    let timeout = DispatchWorkItem { [weak self] in
        self?.coordinator.handle(.dragExited) // Force exit
        self?.logCriticalError("Drag session timeout")
    }
    dragTimeoutTimer = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
}

func handleDragExited() {
    dragTimeoutTimer?.cancel()
    coordinator.handle(.dragExited)
}
```

---

#### **Case 4: System Events Arrive Back-to-Back**
**Trigger**: Multiple `.systemEventPosted` within milliseconds  
**Current**: Coordinator has event queue (reentrant safe)  
**Additional Safety**:
```swift
// Rate limiting for system events
private var lastSystemEventTime: Date?
private let systemEventRateLimit: TimeInterval = 0.5 // 500ms

func handleSystemEvent(_ kind: Activity.Kind) {
    let now = Date()
    
    if let lastTime = lastSystemEventTime,
       now.timeIntervalSince(lastTime) < systemEventRateLimit {
        // Too soon, drop event
        logPerformanceWarning("System event rate-limited: \(kind)")
        return
    }
    
    lastSystemEventTime = now
    coordinator.handle(.systemEventPosted(kind: kind))
}
```

---

#### **Case 5: Sleep/Wake/Display Change**
**Trigger**: `NSApplication.didChangeScreenParametersNotification`  
**Current**: Calls `handleScreenConfigChange()` (repositions only)  
**Additional Safety**:
```swift
@objc func handleSystemWake() {
    // Validate entire state on wake
    validateWindowPosition()
    detectStateDesync()
    
    // Refresh screen assignment
    updateActiveScreen()
    
    // If state is inconsistent, force recovery
    if hasInconsistentState() {
        forceRecoveryState()
    }
}

func hasInconsistentState() -> Bool {
    // Check invariants
    guard let window = self.window else { return true }
    
    return window.level != .statusBar
        || window.ignoresMouseEvents
        || (overlayMode != (interactionState.isExpanded ? .expanded : .compact))
}
```

**Register for wake notification**:
```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(handleSystemWake),
    name: NSWorkspace.didWakeNotification,
    object: nil
)
```

---

## STEP 4: OBSERVABILITY & DEBUG SAFETY

### Lightweight Diagnostics (Debug Only)

#### **State Snapshot (One-Line)**
```swift
extension AppState {
    var stateSnapshot: String {
        "State[\(interactionState)|\(overlayMode)|\(isOverlayVisible)|\(visibilityReason)]"
    }
}

// Usage in logs:
print("⚠️ Desync detected: \(appState.stateSnapshot)")
```

#### **Transition Logging (Debug Only)**
```swift
#if DEBUG
func logTransition(_ from: IslandInteractionState, _ to: IslandInteractionState, _ event: InteractionEvent) {
    let timestamp = Date().timeIntervalSince1970
    print("[\(timestamp)] \(from) --[\(event)]--> \(to)")
}
#endif
```

#### **Illegal Transition Warning**
```swift
func logIllegalTransition(_ state: IslandInteractionState, _ event: InteractionEvent) {
    #if DEBUG
    print("⚠️ ILLEGAL: \(state) + \(event) at \(Date())")
    #endif
    
    // Production: silent log to crash reporter
    #if !DEBUG
    logTelemetry("illegal_transition", ["state": "\(state)", "event": "\(event)"])
    #endif
}
```

#### **Force Reset API (Hidden, Debug Only)**
```swift
#if DEBUG
extension AppState {
    func forceReset() {
        print("🔴 FORCE RESET")
        interactionState = .idle
        overlayMode = .compact
        isOverlayVisible = true
        visibilityReason = .none
        payload = .none
        hint = nil
        lastCopiedAt = nil
    }
}
#endif
```

**Access via menu** (debug builds only):
```swift
#if DEBUG
let resetItem = NSMenuItem(title: "Force Reset Overlay", action: #selector(forceResetOverlay), keyEquivalent: "r")
statusMenu.addItem(resetItem)
#endif
```

---

### CPU/Memory Monitoring (Production)

```swift
import os.log

private let performanceLogger = Logger(subsystem: "com.yourapp.notch", category: "performance")

func logPerformanceSnapshot() {
    let memory = reportMemoryUsage()
    let cpu = reportCPUUsage()
    
    if memory > 100_000_000 { // 100MB
        performanceLogger.warning("High memory: \(memory) bytes")
    }
    
    if cpu > 5.0 { // 5%
        performanceLogger.warning("High CPU: \(cpu)%")
    }
}

// Check every 60 seconds (low overhead)
Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
    logPerformanceSnapshot()
}
```

---

## STEP 5: PERMISSION & COMPLIANCE CHECK

### Private API Audit
✅ **No private APIs detected**
- All `NSEvent`, `NSPanel`, `NSWindow` APIs are public
- No runtime method swizzling
- No undocumented symbols

### Event Interception Audit
🔴 **Global Event Monitors Found** (See Issue #1, #2)

**Current Usage**:
1. `HoverManager`: Global `.mouseMoved` (❌ **Remove**)
2. `HotKeyManager`: Global `.keyDown` (⚠️ **Justify or Replace**)
3. `OverlayWindowController`: Global `.keyDown` (ESC) (✅ **OK — only when expanded**)
4. `OverlayWindowController`: Global `.leftMouseDown` (outside-click) (✅ **OK — only when expanded**)

**Justification Required**:
- ESC monitoring: Only active when overlay is expanded (reasonable)
- Outside-click: Only active when overlay is expanded (reasonable)
- **Hotkey monitoring**: Needs better justification (suggest Carbon API)
- **Mouse movement**: NO justification possible (must remove)

### UI Impersonation Audit
⚠️ **Potential Concern** (See Issue #3)

**Mitigation**:
- Add subtle app branding
- Use non-system colors
- Clear "third-party" disclosure in App Store listing

---

## STEP 6: RELEASE GATING CHECKLIST

### Manual QA Scenarios (Must Pass)

#### **Basic Interaction**
- [ ] Click compact → expands
- [ ] ESC in expanded → collapses
- [ ] Outside click → collapses
- [ ] Drag file over → expands
- [ ] Drag file away (no drop) → collapses
- [ ] Drop file → stays expanded, file in tray

#### **Multi-Click Stress**
- [ ] Rapid click 20 times (1 sec) → no crash, state stable
- [ ] Click-drag-click-drag (rapid) → no stuck states

#### **Multi-Monitor**
- [ ] Overlay appears on active monitor only
- [ ] Switch monitors → overlay repositions
- [ ] Disconnect monitor → overlay moves to remaining screen

#### **Full-Screen**
- [ ] Enter full-screen app → overlay still visible
- [ ] Exit full-screen → overlay still works
- [ ] Overlay doesn't block full-screen controls

#### **Long-Running**
- [ ] Run 8 hours → CPU <0.5%, memory <60MB
- [ ] 1000 state transitions → no leaked monitors/timers

#### **Sleep/Wake**
- [ ] Sleep Mac → wake → overlay repositions correctly
- [ ] Disconnect display → sleep → reconnect → overlay works

#### **Permission Denial**
- [ ] Deny accessibility → app doesn't crash
- [ ] HoverManager gracefully disabled if permission denied

---

### "This Must NEVER Happen" Cases

❌ **NEVER**: Overlay blocks menu bar access  
❌ **NEVER**: Overlay traps input (can't click through when idle)  
❌ **NEVER**: App activates unexpectedly  
❌ **NEVER**: CPU >2% when idle  
❌ **NEVER**: Memory grows unbounded  
❌ **NEVER**: Crash on screen disconnect  
❌ **NEVER**: Stuck in expanded state (can't dismiss)  

---

### CPU / Memory Idle Expectations

| Condition | CPU Target | Memory Target |
|-----------|------------|---------------|
| Overlay hidden (alpha=0) | <0.1% | <40MB |
| Overlay visible (idle) | <0.5% | <50MB |
| Overlay visible (active) | <1.0% | <60MB |
| After 24 hours | <0.5% | <60MB (stable) |

**Current Risk**:
🔴 HoverManager likely causes 3-5% CPU due to global mouse tracking

---

### Window Behavior Verification Matrix

| State | Alpha | Level | Hit-Test | Drag-Dest | Monitors |
|-------|-------|-------|----------|-----------|----------|
| idle | 1.0 | .statusBar | ❌ | ✅ | [] |
| armed | 1.0 | .statusBar | ❌ | ✅ | [] |
| active | 1.0 | .statusBar | ✅ | ✅ | [ESC, outside-click] |
| pinned | 1.0 | .statusBar | ✅ | ✅ | [ESC] |

Verify each state manually:
- [ ] idle: Can't click inside overlay (non-interactive)
- [ ] idle: Can drag file over (drag detection works)
- [ ] active: Can click buttons inside overlay
- [ ] active: ESC collapses overlay
- [ ] pinned: Outside-click ignored

---

### App Store Reviewer Red Flags (Mitigation)

🚩 **"Why does this app track my mouse?"**  
✅ Mitigation: Remove HoverManager global tracking entirely

🚩 **"Why does this app monitor my keyboard?"**  
✅ Mitigation: Use Carbon HotKey API OR provide clear opt-out

🚩 **"Does this imitate macOS UI?"**  
✅ Mitigation: Add "third-party utility" disclaimer, distinct branding

🚩 **"What permissions does this need?"**  
✅ Mitigation: Info.plist usage descriptions, first-run explanation UI

🚩 **"Can I disable the intrusive features?"**  
✅ Mitigation: Settings UI with toggles for hover, hotkeys, clipboard

---

## FINAL VERDICT

### This Is v1.0-Ready ONLY IF:

✅ **HoverManager global mouse tracking is REMOVED**  
✅ **HotKeyManager uses Carbon API or requires explicit user setup**  
✅ **InteractionCoordinator is wired (reentrant safety)**  
✅ **Safe-fail recovery implemented**  
✅ **Info.plist permission descriptions added**  
✅ **Settings UI added (opt-out for intrusive features)**  
✅ **All manual QA scenarios pass**  
✅ **CPU idle <0.5%, memory <60MB verified**  

### Current Readiness: 🔴 **NOT READY**

**Critical Blockers**:
1. HoverManager is App Store poison (global mouse tracking)
2. No user-facing permission explanations
3. No opt-out for intrusive features
4. Coordinator not wired (state desync risk)

### Estimated Remediation Time

- Remove HoverManager global tracking: 2 hours
- Fix HotKeyManager (Carbon API): 4 hours
- Add Info.plist descriptions: 1 hour
- Add Settings UI (toggles): 8 hours
- Wire InteractionCoordinator: 8 hours (already designed)
- Implement safe-fail recovery: 4 hours
- Full QA regression: 8 hours
- **Total**: ~35 hours (4-5 days)

---

## RECOMMENDATION

**DO NOT submit to App Store yet.**

The app is architecturally sound but has **critical compliance issues** that will likely cause rejection.

**Priority fixes**:
1. 🔴 **CRITICAL**: Remove HoverManager global tracking
2. 🔴 **CRITICAL**: Add permission explanations
3. 🟡 **HIGH**: Wire InteractionCoordinator
4. 🟡 **HIGH**: Add Settings UI

After fixes, this will be **v1.0-ready and safe to ship**.

---

**Date**: 2026-01-10  
**Reviewer**: macOS Engineer + QA Lead + App Store Reviewer  
**Next Review**: After critical fixes implemented
