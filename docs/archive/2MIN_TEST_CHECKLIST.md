# 2-Minute Test Checklist

## SETUP (10 seconds)
1. Build and run app
2. Check notch area
3. Verify **Debug HUD visible** in bottom-left corner showing:
   - Visibility: HIDDEN
   - Reason: none
   - Last Event: (none)

---

## TEST 1: CLIPBOARD PULSE (15 seconds)

**Action**: Copy any text (Cmd+C)

**Expected within 300ms**:
- ✅ Overlay appears (pill)
- ✅ Debug HUD shows:
  - Visibility: VISIBLE
  - Reason: clipboard
  - Last Event: `Clipboard: text (...)`
  - Timestamp: updates to current time
- ✅ Pill shows clipboard icon + text preview
- ✅ After 1.5 seconds, overlay disappears
- ✅ Debug HUD shows: Visibility: HIDDEN

**Console check**:
```
⏱️ [HH:MM:SS.mmm] Clipboard: text (...)
🟢 AppState.showOverlay(reason: clipboard)
```

**CRITICAL**: If overlay doesn't appear, drag detection will also fail.

---

## TEST 2: FILE DRAG HOVER (20 seconds)

**Action**: 
1. Open Finder
2. Select any file
3. Start dragging (hold mouse button down)
4. Hover over notch area (DON'T release yet)

**Expected within 150ms**:
- ✅ Overlay appears (pill)
- ✅ Debug HUD shows:
  - Visibility: VISIBLE
  - Reason: dragHover
  - Last Event: `Drag: entered notch zone`
  - Timestamp: updates
- ✅ Pill highlights subtly

**Move drag away from notch**:
- ✅ Debug HUD shows: Last Event: `Drag: exited notch zone`
- ✅ Overlay stays visible (doesn't auto-hide)

**Console check**:
```
⏱️ [HH:MM:SS.mmm] Drag: entered notch zone
🟢 AppState.showOverlay(reason: dragHover)
```

**CRITICAL**: If this doesn't work, window is ignoring drag events.

---

## TEST 3: FILE DROP (25 seconds)

**Action**: 
1. Drag file from Finder onto notch
2. Release mouse button (drop)

**Expected immediately**:
- ✅ Overlay expands to panel
- ✅ Debug HUD shows:
  - Visibility: VISIBLE
  - Reason: dropComplete
  - Last Event: `Drop: 1 item(s)`
  - Activities: 1
  - Top: drop
- ✅ Activity shows "Items Added: Added 1 item(s)"
- ✅ File appears in tray with icon + name
- ✅ Tray shows action buttons: Reveal / Copy Path / Remove

**Click "Reveal in Finder"**:
- ✅ Finder opens with file selected

**Wait 4 seconds**:
- ✅ Overlay auto-hides
- ✅ Debug HUD shows: Visibility: HIDDEN, Reason: none

**Console check**:
```
⏱️ [HH:MM:SS.mmm] Drag: entered notch zone
⏱️ [HH:MM:SS.mmm] Drop: 1 item(s)
🟢 AppState.showOverlay(reason: dropComplete)
🔴 ActivityCenter.post(): drop | title=Items Added | total activities=1
```

---

## TEST 4: MULTI-FILE DROP (15 seconds)

**Action**: 
1. Select 3 files in Finder
2. Drag all onto notch
3. Drop

**Expected**:
- ✅ Debug HUD: Last Event: `Drop: 3 item(s)`
- ✅ Activity: "Added 3 item(s)"
- ✅ All 3 files in tray
- ✅ Auto-hides after 4 seconds

---

## TEST 5: SPACES SWITCH (15 seconds)

**Action**:
1. Copy text (trigger overlay)
2. Wait for overlay to appear
3. Switch to different Space (Ctrl+→)
4. Switch back to original Space

**Expected**:
- ✅ Overlay still visible
- ✅ Positioned correctly at notch
- ✅ Debug HUD still shows correct state

**Action**: Drop file in Space 2
**Expected**:
- ✅ Overlay appears in Space 2
- ✅ Drop works correctly

---

## TEST 6: FULLSCREEN APP (15 seconds)

**Action**:
1. Open Safari
2. Enter fullscreen (⌃⌘F)
3. Copy text

**Expected**:
- ✅ Overlay appears over fullscreen app
- ✅ Debug HUD visible
- ✅ Positioned at notch

---

## TEST 7: DEBUG HUD REAL-TIME (10 seconds)

**Action**: Watch Debug HUD while performing actions

**Expected behavior**:
- ✅ Visibility toggles: HIDDEN ↔ VISIBLE
- ✅ Reason changes: none → clipboard → none
- ✅ Last Event updates with description
- ✅ Timestamp shows milliseconds
- ✅ Activities count increments/decrements
- ✅ Top activity shows current kind

---

## TEST 8: MANUAL DISMISS (10 seconds)

**Action**:
1. Drop file (overlay expands)
2. Click X button in top-right

**Expected**:
- ✅ Overlay disappears immediately
- ✅ Debug HUD shows: Visibility: HIDDEN
- ✅ Console: `🔴 AppState.hideOverlay()`

---

## PASS CRITERIA

If ALL 8 tests pass:
✅ Clipboard detection works (< 300ms)
✅ Drag-hover detection works (< 150ms)
✅ File drop works (tray populated, actions functional)
✅ Auto-hide works (1.5s clipboard, 4s drop)
✅ Overlay survives Spaces + fullscreen
✅ Debug HUD provides real-time feedback

**App is REACTIVE and DEBUGGABLE.**

---

## FAIL SCENARIOS & FIXES

### Overlay never appears on clipboard
- Check: ClipboardManager running? Console shows clipboard detection?
- Check: AppState.isOverlayVisible = true after copy?
- Check: Window alphaValue restored to 1.0 in show()?

### Drag-hover doesn't trigger
- Check: Window alphaValue = 0 when hidden (not orderOut)?
- Check: ignoresMouseEvents = false always?
- Check: Drop handler on NotchOverlayView root (not child)?

### Drop doesn't work
- Check: Console shows "Drag: entered notch zone"?
- Check: isTargeted onChange firing?
- Check: handleDrop() called?

### Debug HUD not visible
- Check: DebugHUD added to NotchOverlayView ZStack?
- Check: Window level = .statusBar?

### Overlay disappears after Spaces switch
- Check: collectionBehavior includes .canJoinAllSpaces?
- Check: handleScreenConfigChange() repositions window?

---

## TOTAL TIME: ~2 minutes

Run all tests sequentially. If any fail, consult fail scenarios above.

