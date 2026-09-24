# UX Polish Pass – QA Checklist

**Goal**: Validate all UX polish enhancements work as designed.  
**Build**: Phase 5 – UX Polish Pass  
**Time**: ~5 minutes

---

## Test Cases

### 1. Magnetic Expand (Drag Hover)
**Action**: Drag a file from Finder and hover over the notch overlay (do NOT drop yet)  
**Expected**:
- Overlay instantly appears (if hidden)
- Pill **auto-expands** to full panel with spring animation
- Dashed border overlay appears around drop zone
- Smooth, bouncy feel (spring physics)

**Pass/Fail**: ☐

---

### 2. Magnetic Collapse (Drag Exit)
**Action**: While dragging over notch (from Test 1), drag **away** from the notch zone  
**Expected**:
- Dashed border disappears
- Panel **auto-collapses** back to compact pill with spring animation
- Overlay hides after brief delay (if no activities)

**Pass/Fail**: ☐

---

### 3. Drop Target Visual
**Action**: Drag file over notch and observe the drop target overlay  
**Expected**:
- Dashed rounded rectangle appears
- Animates in with spring (scale + opacity)
- Matches the panel shape/size
- Does not block drag/drop interaction

**Pass/Fail**: ☐

---

### 4. Smooth Module Transitions (Now Playing → Activity)
**Action**: 
1. Start playing music in Apple Music (Now Playing pill appears)
2. Copy some text to clipboard (Clipboard activity should pulse)

**Expected**:
- Pill content crossfades with subtle scale (0.95 → 1.0)
- No jarring flicker or jump
- Transition duration ~0.25s, easeOut curve

**Pass/Fail**: ☐

---

### 5. Smooth Module Transitions (Activity → Default)
**Action**: Wait for clipboard activity to expire (5s)  
**Expected**:
- Activity pill fades out + scales down slightly
- Default pill (clock icon) fades in + scales up
- Smooth crossfade, no blank frames

**Pass/Fail**: ☐

---

### 6. Activity Dismiss Button
**Action**: Trigger a clipboard activity, then click the **X button** on the activity pill  
**Expected**:
- Activity immediately removed from ActivityCenter
- Pill transitions to next priority module or default
- No crash, no duplicate dismissals

**Pass/Fail**: ☐

---

### 7. Settings Panel – Open
**Action**: Click status bar icon → **Settings** menu item  
**Expected**:
- Settings window opens centered on screen
- Shows title "Overlay Settings"
- 3 toggle switches visible (Drag & Drop, Now Playing, Clipboard)
- Overlay Scale slider visible (80% – 120%)
- Reset Overlay button visible
- Close button visible

**Pass/Fail**: ☐

---

### 8. Settings Panel – Toggle Features
**Action**: 
1. Turn OFF "Enable Clipboard Pulse"
2. Copy text to clipboard

**Expected**:
- No clipboard activity appears
- ClipboardManager should not trigger overlay

**Action (cont.)**:
3. Turn OFF "Enable Now Playing"
4. Play music in Apple Music

**Expected**:
- Now Playing pill does not appear
- Overlay does not show media controls

**Action (cont.)**:
5. Turn OFF "Enable Drag & Drop"
6. Drag a file over the notch

**Expected**:
- Overlay does NOT expand on hover
- Drop is ignored (no items added to tray)

**Pass/Fail**: ☐

---

### 9. Settings Panel – Overlay Scale
**Action**: 
1. Move slider to 120% (max)
2. Trigger any activity to show the overlay

**Expected**:
- Overlay pill/panel is visibly larger (1.2x scale)
- Repositions correctly at notch center

**Action (cont.)**:
3. Move slider to 80% (min)

**Expected**:
- Overlay shrinks to 0.8x scale
- Still usable, no clipping or layout issues

**Pass/Fail**: ☐

---

### 10. Settings Panel – Reset Overlay
**Action**: 
1. Expand overlay to full panel
2. Change scale to 110%
3. Open Settings → click **Reset Overlay** button

**Expected**:
- Overlay immediately hides
- Overlay scale resets to 100% (1.0)
- Settings window remains open

**Pass/Fail**: ☐

---

## Summary

**Total Tests**: 10  
**Passed**: ☐ / 10  
**Failed**: ☐ / 10  

**Notes**:  
(Add any bugs, edge cases, or observations here)

---

## Regression Checks

Before marking complete, verify these existing features still work:

- [ ] File drop still adds to tray (when Drag & Drop enabled)
- [ ] Tray "Reveal in Finder" button works
- [ ] Tray "Copy Path" button works
- [ ] Tray "Remove" button works
- [ ] Now Playing controls (Play/Pause/Next/Prev) work when media enabled
- [ ] Timer module still functions
- [ ] Debug HUD still shows state updates (bottom-left)
- [ ] ESC key collapses expanded panel
- [ ] Click outside expanded panel collapses it
- [ ] Hotkey (Option+Space) toggles overlay visibility
