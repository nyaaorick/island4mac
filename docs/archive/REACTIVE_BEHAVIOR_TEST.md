# Reactive Behavior Testing Checklist

## NEW BEHAVIOR MODEL

**Default State**: Overlay is HIDDEN (not visible)

**Visibility Triggers**: Overlay only appears when a real system event occurs

---

## TEST 1: APP LAUNCH (HIDDEN BY DEFAULT)

**Steps**:
1. Build and run app
2. Look at notch area

**Expected**:
- ✅ Overlay is **NOT visible** on launch
- ✅ No pill, no clock icon, nothing
- ✅ Console shows: `🔴 AppState.hideOverlay()` or `visibilityReason: none`

**CRITICAL**: If you see a clock pill on launch, the app is broken.

---

## TEST 2: CLIPBOARD PULSE (< 300ms reaction)

**Steps**:
1. Copy any text (Cmd+C anywhere)
2. Watch notch area

**Expected**:
- ✅ Overlay **appears immediately** (< 300ms)
- ✅ Shows pill with clipboard icon + text preview
- ✅ Console: `🟢 AppState.showOverlay(reason: clipboard)`
- ✅ Console: `🟡 ClipboardManager.tick(): Detected text change`
- ✅ After **1.5 seconds**, overlay **disappears automatically**
- ✅ Console: `🟠 OverlayWindowController: All activities expired, auto-hiding`
- ✅ Console: `🔴 AppState.hideOverlay()`

**CRITICAL**: If overlay doesn't disappear after 1.5s, auto-hide is broken.

---

## TEST 3: CLIPBOARD IMAGE

**Steps**:
1. Copy an image (screenshot, from Photos.app, etc.)
2. Watch notch area

**Expected**:
- ✅ Overlay appears with "Image copied" + photo icon
- ✅ Disappears after 1.5 seconds

---

## TEST 4: FILE DROP - MAGNETIC EXPAND

**Steps**:
1. Start dragging any file from Finder
2. Hover over notch area (don't drop yet)

**Expected**:
- ✅ Overlay **appears instantly** when drag enters notch zone
- ✅ Console: `🧲 PillView: Drag detected, triggering magnetic expand`
- ✅ Console: `🟢 AppState.showOverlay(reason: dragHover)`
- ✅ Pill shows with subtle highlight
- ✅ Move drag away → overlay stays visible (doesn't hide)

---

## TEST 5: FILE DROP - COMPLETE

**Steps**:
1. Drag file onto notch
2. Drop it

**Expected**:
- ✅ Overlay expands to panel
- ✅ Console: `📎 PillView.handleDropOnPill: 1 item(s) dropped`
- ✅ Console: `🟢 AppState.showOverlay(reason: dropComplete)`
- ✅ Activity shows "Items Added: Added 1 item(s)"
- ✅ File appears in tray
- ✅ After **4 seconds**, overlay **auto-hides**
- ✅ Console: `🟠 OverlayWindowController: All activities expired, auto-hiding`

---

## TEST 6: FILE DROP - MULTIPLE FILES

**Steps**:
1. Select 3 files in Finder
2. Drag all onto notch
3. Drop

**Expected**:
- ✅ Activity shows "Added 3 item(s)"
- ✅ All 3 files in tray
- ✅ Auto-hides after 4 seconds

---

## TEST 7: TRAY ACTIONS (REVEAL IN FINDER)

**Steps**:
1. Drop a file onto overlay
2. Click "Reveal in Finder" button in tray

**Expected**:
- ✅ Finder opens with file selected
- ✅ Overlay remains visible (user action doesn't trigger auto-hide)

---

## TEST 8: MANUAL DISMISS (X BUTTON)

**Steps**:
1. Drop a file (overlay expands)
2. Click **X** button in top-right corner

**Expected**:
- ✅ Console: `❌ ExpandedPanelView.collapsePanel: Hiding overlay`
- ✅ Console: `🔴 AppState.hideOverlay()`
- ✅ Overlay **immediately hides**
- ✅ Does NOT just collapse to pill, fully disappears

---

## TEST 9: TIMER (5 MINUTES)

**Steps**:
1. Click menu bar icon
2. Select "Start Timer (5 min)"

**Expected**:
- ✅ Overlay **appears**
- ✅ Console: `🟢 AppState.showOverlay(reason: timer)`
- ✅ Shows pill with timer icon + "5:00" countdown
- ✅ Countdown updates every second: "4:59", "4:58", etc.
- ✅ After 5 minutes:
  - Activity changes to "Timer Done"
  - System beep plays
  - Overlay **auto-hides after 2 seconds**

---

## TEST 10: FORCE TEST ACTIVITY (DEBUG)

**Steps**:
1. Click menu bar icon
2. Select "[DEBUG] Force Test Activity"

**Expected**:
- ✅ Overlay appears
- ✅ Shows "TEST ACTIVITY" with checkmark
- ✅ Console: `🟣 FORCE TEST ACTIVITY`
- ✅ Console: `🟢 AppState.showOverlay(reason: userExpanded)`
- ✅ Overlay stays visible (user-triggered, no auto-hide)
- ✅ After 5 seconds, activity expires but overlay stays (userExpanded reason)
- ✅ Must click X to dismiss

---

## TEST 11: NO ACTIVITY = HIDDEN

**Steps**:
1. Wait 30 seconds without copying/dragging/starting timer
2. Watch notch area

**Expected**:
- ✅ Overlay is **completely hidden**
- ✅ No clock pill, no decoration, nothing
- ✅ Console shows minimal/no logging (idle state)

**CRITICAL**: If you see a persistent clock pill, the app is broken.

---

## TEST 12: RAPID CLIPBOARD CHANGES

**Steps**:
1. Copy text 5 times in rapid succession (< 1 second between copies)

**Expected**:
- ✅ Overlay shows for each copy
- ✅ 1.5s timer **resets** on each copy
- ✅ Final copy: overlay stays visible for full 1.5s before hiding
- ✅ No crashes, no spam

---

## TEST 13: ESCAPE KEY (WHEN EXPANDED)

**Steps**:
1. Drop a file (overlay expands)
2. Press **Escape** key

**Expected**:
- ✅ Overlay **hides completely**
- ✅ Does NOT just collapse to pill

---

## TEST 14: OUTSIDE CLICK (WHEN EXPANDED)

**Steps**:
1. Drop a file (overlay expands)
2. Click anywhere outside overlay

**Expected**:
- ✅ Overlay **hides completely**

---

## CONSOLE OUTPUT REFERENCE

**Good flow (clipboard)**:
```
🟡 ClipboardManager.tick(): Detected text change, posting activity...
🟢 AppState.showOverlay(reason: clipboard)
📺 Overlay showing
🔴 ActivityCenter.post(): clipboard | title=Clipboard | total activities=1
✅ ClipboardManager: Posted clipboard activity + triggered visibility
🟢 PillView.body: topActivity=clipboard | activities.count=1
[Wait 1.5s]
🟠 OverlayWindowController: All activities expired, auto-hiding
🔴 AppState.hideOverlay()
📺 Overlay hiding
```

**Good flow (file drop)**:
```
🧲 PillView: Drag detected, triggering magnetic expand
🟢 AppState.showOverlay(reason: dragHover)
📎 PillView.handleDropOnPill: 1 item(s) dropped
🟢 AppState.showOverlay(reason: dropComplete)
🔴 ActivityCenter.post(): drop | title=Items Added | total activities=1
[Wait 4s]
🟠 OverlayWindowController: All activities expired, auto-hiding
🔴 AppState.hideOverlay()
```

---

## SIGN-OFF

If ALL 14 tests pass:
- ✅ App is **state-driven** (hidden by default)
- ✅ App is **reactive** (< 300ms response)
- ✅ App is **self-managing** (auto-hide works)
- ✅ App feels **alive**, not like a shell

**Ready to ship MVP Module A (Clipboard Pulse) + Module B (File Drop Tray).**

Module C (Media Now Playing) requires additional MediaManager implementation.

