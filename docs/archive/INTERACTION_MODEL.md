# Production Interaction Model

## Design Philosophy
This notch overlay behaves like a **macOS system utility**, not a demo or floating tool.
It follows patterns established by real production apps: NotchNook, BoringNotch, NotchDrop, and Atoll.

---

## Four-State Model

### **idle**
- **Visual**: Visible compact pill at notch location
- **Window**: Alpha=1, accepts events, compact bounds
- **Behavior**: Passive presence, no interaction
- **Transitions**:
  - hover → **armed**
  - click → **active**
  - drag enter → **active**

### **armed**
- **Visual**: Compact pill + subtle glow (accentColor.opacity(0.2))
- **Window**: Alpha=1, accepts events, compact bounds
- **Behavior**: Hover feedback only, NO expansion
- **Transitions**:
  - hover exit → **idle**
  - click → **active**
  - drag enter → **active**

### **active**
- **Visual**: Expanded panel with full UI
- **Window**: Alpha=1, accepts events, expanded bounds
- **Behavior**: Fully interactive, shows content and controls
- **Transitions**:
  - outside click → **idle**
  - ESC → **idle**
  - pin button → **pinned**

### **pinned**
- **Visual**: Expanded panel + pin indicator (pin.fill icon)
- **Window**: Alpha=1, accepts events, expanded bounds
- **Behavior**: Locked open, ignores outside clicks
- **Transitions**:
  - unpin button → **active**
  - ESC → **idle** (force close)
  - close button → **idle** (force close)

---

## Interaction Rules

### **Hover (NEVER expands)**
```
idle + hover      → armed  (120ms debounce, subtle glow)
armed + hover exit → idle  (immediate)
active + hover     → no-op (already expanded)
```

### **Click (Always activates)**
```
idle + click   → active (instant)
armed + click  → active (instant)
active + click → no-op (handle internal UI)
```

### **Drag & Drop (Highest priority)**
```
ANY state + dragEntered → active (reason: .dragHover)
active + dragExited     → idle (only if reason == .dragHover)
active + drop complete  → active (reason: .dropComplete, stay expanded)
```

### **Dismiss**
```
active + outside click → idle (if canDismiss)
active + ESC          → idle (if canDismiss)
pinned + ESC          → idle (force close)
pinned + close button → idle (force close)
```

### **System Events**
```
clipboard change      → active (reason: .clipboard, auto-hide after 1.5s)
now playing change    → active (reason: .nowPlaying, auto-hide after 2s)
timer expiry          → active (reason: .timer, auto-hide after 2s)
activity expires      → idle (if no other activities and !pinned)
```

---

## Window Configuration

### **NSPanel Setup (Non-Activating)**
```swift
let window = PassthroughPanel(
    contentRect: ...,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

window.hidesOnDeactivate = false  // Stay visible when app loses focus
window.worksWhenModal = true      // Work in modal contexts
window.ignoresMouseEvents = false // ALWAYS accept events for drag detection
window.level = .statusBar
window.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .ignoresCycle
]
```

### **Visibility Control**
- **NEVER use `orderOut()`** — breaks drag detection
- **Use `alphaValue` only**:
  ```swift
  show() → window.alphaValue = 1.0
  hide() → window.alphaValue = 0.0  // Still receives drag events
  ```

### **Non-Activating Behavior**
- App NEVER comes to foreground on click
- Window accepts key events without activating app
- ESC and outside-click work without stealing focus

---

## State Machine Implementation

### **AppState.swift**
```swift
// Default state: visible compact (idle)
@Published var isOverlayVisible: Bool = true  // NOT false
@Published var interactionState: IslandInteractionState = .idle

// State transitions
func armOverlay()         // idle → armed
func disarmOverlay()      // armed → idle
func activateOverlay(reason:) // any → active
func deactivateOverlay()  // active → idle (if canDismiss)
func pinOverlay()         // active → pinned
func unpinOverlay()       // pinned → active
func forceCloseOverlay()  // any → idle (force)
```

### **UI Components**
- **PillView**: Compact state, handles tap → activate
- **ExpandedPanelView**: Full state, pin/close buttons, tray
- **NotchOverlayView**: Root, drag detection, hover handlers

---

## Visual Feedback

### **Armed State**
```swift
.shadow(
    color: isArmed ? Color.accentColor.opacity(0.2) : .clear,
    radius: 12
)
```

### **Drag Target**
```swift
.shadow(
    color: isDropTargeted ? Color.accentColor.opacity(0.6) : .clear,
    radius: 12
)
```

### **Animations**
- State changes: **instant** (no delay)
- UI transitions: **spring(response: 0.4, dampingFraction: 0.7)**
- Reduce motion: **linear(duration: 0.15)**

---

## Testing Checklist

### **Basic Interactions**
- [ ] Hover: idle → armed (glow appears)
- [ ] Hover exit: armed → idle (glow disappears)
- [ ] Click (idle): idle → active (expands)
- [ ] Click (armed): armed → active (expands)
- [ ] ESC (active): active → idle (collapses)
- [ ] Outside click (active): active → idle (collapses)

### **Drag & Drop**
- [ ] Drag over (idle): idle → active (expands)
- [ ] Drag exit (no drop): active → idle (collapses)
- [ ] Drop files: files added to tray, overlay stays active
- [ ] Multiple drops: all files received

### **Pin State**
- [ ] Pin button (active): active → pinned
- [ ] Outside click (pinned): no-op (stays pinned)
- [ ] ESC (pinned): pinned → idle (force close)
- [ ] Unpin button (pinned): pinned → active

### **System Behavior**
- [ ] App never activates on click
- [ ] Works across Spaces
- [ ] Works with fullscreen apps
- [ ] Works on multiple displays
- [ ] Doesn't steal keyboard focus

### **Activity System**
- [ ] Clipboard change: shows activity, auto-hides after 1.5s
- [ ] Now playing: shows media controls
- [ ] Timer: shows timer UI
- [ ] Activity expiry: collapses if not pinned

---

## Common Mistakes to AVOID

❌ **Hover triggers expansion** — Only armed state, never active
❌ **Using orderOut() to hide** — Breaks drag detection
❌ **Window activates app** — Must use .nonactivatingPanel
❌ **Animation-dependent state** — State changes first, UI animates separately
❌ **Magic timers** — All delays explicit with OverlayVisibilityReason
❌ **Hidden by default** — Start in idle (visible compact), not hidden

---

## Success Criteria

✅ Feels like a **system utility**, not a floating window
✅ Behaves like **NotchNook/BoringNotch** (industry standard)
✅ Never surprises the user with unexpected activation
✅ Predictable, boring, professional behavior
✅ Would pass App Store review
