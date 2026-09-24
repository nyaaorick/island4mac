# Acceptance Test Plan - Dynamic Island Overlay
## Goal: 100% Reliable, Production-Quality Interaction

---

## Test Environment
- **Build**: DEBUG mode with hit-test diagnostic overlays enabled
- **Xcode**: Run scheme `Mac灵动岛` 
- **Display**: Main screen, standard resolution
- **Initial State**: Fresh app launch, clipboard history cleared

---

## A. OPEN RELIABILITY TEST
### Acceptance Criteria
- 100% success rate over 20 open/close cycles
- No black blocks or stuck states
- Smooth animated transitions every time

### Test Procedure
1. Launch app in Xcode (DEBUG mode)
2. Verify compact pill appears at top center (~280×52px)
3. Perform 20 cycles of:
   - Click overlay to expand
   - Wait for animation to complete
   - Observe expanded size (should be >= 640×320)
   - Click outside overlay or press ESC to collapse
   - Wait for animation to complete
   - Verify returns to compact pill
4. Record any failures: stuck states, black blocks, frozen animations

### Expected Result
✅ 20/20 successful cycles
✅ No visual glitches
✅ Smooth transitions

---

## B. SIZE & VISUAL USABILITY TEST
### Acceptance Criteria
- Expanded overlay >= 640×320 (minimum for 3-zone layout)
- Compact pill remains ~280×52
- Content fully visible and readable when expanded
- No content clipping or overflow

### Test Procedure
1. Launch app, observe compact size
2. Click to expand
3. Measure window dimensions using Xcode's View Debugger or screenshot
4. Verify DEBUG watermark shows correct mode (EXP, M/L/XL)
5. Add 0 items: verify expanded size still >= 640×320
6. Add 5 items: verify size adjusts appropriately (M→L)
7. Add 15 items: verify size adjusts appropriately (L→XL)
8. Check all zones visible: Z1 (command), Z2 (grid), Z3 (quick actions)

### Expected Result
✅ Compact: ~280×52
✅ Expanded with 0 items: >= 640×320 (mode M)
✅ Expanded with 5 items: >= 640×320 (mode M or L)
✅ Expanded with 15 items: >= 640×320 (mode L or XL)
✅ All content readable, no clipping

---

## C. INTERACTION RELIABILITY TEST - Zero Items
### Acceptance Criteria
- All buttons clickable with empty clipboard
- ~100% click success rate during rapid interaction
- No accidental collapses when clicking buttons

### Test Procedure
1. Launch app, clear clipboard history (use Quick Actions → Clear Clipboard)
2. Expand overlay
3. Verify 0 items shown in content grid
4. Test each button systematically:
   - Search field: click, type, clear
   - Filter pills: click All, Text, Links, Images
   - Quick Actions: Clear Clipboard (disabled), Clear Files (disabled), Downloads, Desktop
5. Rapid interaction test:
   - Click buttons rapidly in random order (20 clicks)
   - Scroll through empty grid
   - Type in search field while clicking elsewhere
6. Record failures: unresponsive clicks, accidental collapses

### Expected Result
✅ All buttons respond to clicks
✅ No accidental collapses when clicking interactive elements
✅ ~100% click success rate (19-20/20 rapid clicks)

---

## C. INTERACTION RELIABILITY TEST - Many Items (10+)
### Acceptance Criteria
- All buttons clickable with 10+ clipboard items
- ~100% click success rate during rapid scroll/interaction
- Scrolling doesn't interfere with button clicks

### Test Procedure
1. Add 15+ items to clipboard (copy text snippets repeatedly)
2. Expand overlay
3. Verify 15+ items shown in content grid
4. Test each button systematically:
   - Search field: click, type, filter items
   - Filter pills: click to filter, verify counts update
   - Scroll through grid smoothly
   - Click individual item cards
   - Hover over items to reveal action buttons (copy, pin, delete)
   - Click action buttons in hover state
5. Rapid interaction test:
   - Scroll while clicking filter pills (10 attempts)
   - Click item cards rapidly while scrolling (20 clicks)
   - Type in search while clicking items
6. Record failures: missed clicks, accidental collapses, scroll interference

### Expected Result
✅ All buttons respond during scroll
✅ Item cards clickable even when grid is scrolling
✅ No accidental collapses
✅ ~100% click success rate (19-20/20 rapid clicks during scroll)

---

## D. NO REGRESSIONS TEST
### Acceptance Criteria
- Clipboard monitoring still works
- Items appear automatically when copied
- No crashes or error spam in console
- Esc key collapses overlay
- Outside-click collapses overlay

### Test Procedure
1. Launch app, expand overlay
2. Copy text from another app (e.g., TextEdit)
3. Verify new item appears in grid immediately
4. Copy 5 more items from various apps
5. Verify all items appear with correct source app icons
6. Test collapse mechanisms:
   - Press ESC key → should collapse
   - Click outside overlay → should collapse
   - Click inside overlay on interactive elements → should NOT collapse
7. Check Xcode console for errors/warnings
8. Monitor for crashes during 5 minutes of normal use

### Expected Result
✅ Clipboard items appear automatically
✅ ESC collapses overlay
✅ Outside-click collapses overlay
✅ Inside-click on buttons does NOT collapse
✅ No crashes
✅ No error spam in console

---

## DEBUG Diagnostic Observations
During all tests, observe DEBUG indicators:
- **Hit-test overlays**: Green (Z1:CMD), Purple (Z3:PIN), Blue (Z2:GRID), Orange (BTN)
- **Watermark**: Shows "EXP • Standard • N items" format
- **🔍 DEBUG indicator**: Top-right corner confirms diagnostic mode

If any overlay is NOT visible, the zone is likely not receiving hit-tests properly.

---

## Pass/Fail Criteria
### PASS = All of:
- A: 20/20 open/close cycles successful
- B: Sizes meet minimums, content fully visible
- C (0 items): ~19-20/20 rapid clicks successful
- C (10+ items): ~19-20/20 rapid clicks during scroll successful
- D: No regressions, clipboard works, no crashes

### FAIL = Any of:
- Stuck states or black blocks
- Size < 640×320 when expanded
- < 18/20 rapid click success rate
- Accidental collapses when clicking buttons
- Clipboard monitoring broken
- Crashes or severe console errors

---

## Rollback Plan (if tests fail)
If ANY test fails:
1. Document exact failure mode with screenshots
2. Revert last architectural changes
3. Apply simpler, more conservative fix
4. Re-test with same acceptance criteria
5. Iterate until all tests pass

---

## Notes
- All tests should be performed in DEBUG mode with diagnostic overlays visible
- Record exact failure counts, not just pass/fail
- If a test fails once, repeat 3 times to check for consistency
- Prioritize reliability over feature complexity
