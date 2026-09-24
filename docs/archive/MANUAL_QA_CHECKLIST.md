# Manual QA Checklist - Mac 灵动岛 MVP

## A) OVERLAY CORE BEHAVIOR

- [ ] **App Launch**: Open the app. Overlay appears at top-center of main screen.
- [ ] **Stay Visible**: Overlay remains visible when switching Spaces.
- [ ] **Hover Expand**: Move mouse over pill (compact mode) → pill expands to full panel with smooth animation.
- [ ] **Hover Collapse**: Move mouse away from expanded panel → panel collapses back to pill after 1 second.
- [ ] **Click Toggle**: Click pill → expands. Click expanded panel's X button → collapses. No focus stealing.
- [ ] **Escape Key**: When expanded, press Escape → collapses back to pill.
- [ ] **Outside Click**: When expanded, click outside overlay → collapses back to pill.
- [ ] **Safe Mode Toggle**: Open menu → toggle "Safe Mode" → hover animations should be disabled, motion reduced.
- [ ] **Safe Mode Persistence**: After enabling Safe Mode, close and reopen app → Safe Mode state persists.

## B) DRAG & DROP - FILES AND APPS

### Drag Files onto Pill (Compact)
- [ ] **Detect Drag**: Drag any file over pill → pill highlights, shows subtle visual feedback.
- [ ] **Auto-Expand**: On drag-over, overlay auto-expands to panel.
- [ ] **Drop Single File**: Drop a .txt file onto pill → Activity shows "Items Added: Added 1 item(s)".
- [ ] **Activity Auto-Dismisses**: After 4 seconds, activity disappears.
- [ ] **Tray Shows Item**: File appears in Tray section at bottom of panel.
- [ ] **Reveal in Finder**: Click "Reveal in Finder" button in tray → Finder opens with file selected.
- [ ] **Copy Path**: Click "Copy Path" → file path is copied to clipboard (can verify by opening Notes and pasting).
- [ ] **Remove from Tray**: Click "Remove" → item disappears from tray instantly, UI doesn't crash.

### Drag Multiple Files
- [ ] **Count Correct**: Drag 3 files onto pill → Activity shows "Added 3 item(s)".
- [ ] **All in Tray**: All 3 files appear in tray list.
- [ ] **Clear All Works**: Click "Clear All" in tray header → all items removed, tray is empty.

### Drag App Bundle (.app)
- [ ] **App Detected**: Drag an .app bundle (e.g., TextEdit) onto pill → Activity posts "Items Added: Added 1 item(s)".
- [ ] **App Icon Shows**: App appears in tray with correct icon and name "TextEdit".
- [ ] **App Marked as App**: Item in tray shows "Open" button instead of "Reveal in Finder".
- [ ] **App Launches**: Click "Open" → app launches correctly.

### Drag Onto Expanded Panel
- [ ] **Works Same**: Drag file onto expanded panel → same behavior as pill.
- [ ] **Count Correct**: Activity shows correct item count.
- [ ] **Tray Updates**: File is added to tray.

### Reject Unsupported
- [ ] **Drag Invalid**: Drag unsupported item type (e.g., text from browser) → if not a file URL, drop is rejected gracefully with error activity.
- [ ] **Error Activity**: Error activity shows briefly with localized message.

## C) CLIPBOARD SIGNAL

### Text Copied
- [ ] **Text Detection**: Copy some text (Cmd+C) → Clipboard activity appears in pill showing first 60 chars of text.
- [ ] **Activity Title**: Activity shows "Clipboard" as title.
- [ ] **Activity Auto-Dismisses**: After 3 seconds, activity auto-dismisses.
- [ ] **No Spam**: Copy same text twice in a row → activity posts only once (duplicate ignored).
- [ ] **Different Text**: Copy different text → new activity posts.

### Image Copied
- [ ] **Image Detection**: Copy an image (from Photos or screenshot) → Activity shows "Image copied" with photo icon.
- [ ] **Auto-Dismiss**: After 3 seconds, activity auto-dismisses.

### CPU Idle
- [ ] **Low Idle CPU**: Let app sit for 30 seconds without copying → Activity monitor shows < 1% CPU usage.
- [ ] **Polling Throttled**: Clipboard polling interval is >= 300ms (check ClipboardManager code).

## D) TRAY - REAL ACTION HUB

### Tray Display
- [ ] **Shows Recent Drops**: Drag 2 files → both appear in tray (most recent first).
- [ ] **Tray Header**: Tray shows "Tray" label with "Clear All" button.
- [ ] **Empty State**: Delete all items → Tray shows "(empty)" message.

### Tray Actions
- [ ] **Reveal**: Click "Reveal in Finder" on a file → Finder opens with file highlighted.
- [ ] **Copy Path**: Click "Copy Path" → path is in clipboard.
- [ ] **Remove**: Click "Remove" → item removed from tray, UI stable.
- [ ] **Clear All**: Click "Clear All" in header → tray empties.

### Missing Files
- [ ] **Handle Missing**: Add a file, delete it from disk, reopen app → tray shows file strikethrough with "(Missing)" label.
- [ ] **Remove Missing**: Click "Remove" on missing file → item removed from tray.

### Persistence
- [ ] **In-Memory Only**: Add files to tray, close app → on reopen, tray still shows items (persisted via UserDefaults).
- [ ] **Survives Relaunch**: Items in tray survive app restart.

## E) TIMER FEATURE

### Start Timer
- [ ] **Menu Item**: Menu shows "Start Timer (5 min)" item.
- [ ] **Click Start**: Click "Start Timer" → Activity posts with timer icon and "5:00" countdown.
- [ ] **Overlay Shows**: Overlay auto-expands and shows activity at top (highest priority).

### Countdown
- [ ] **Updates Every Second**: Activity message updates from "5:00" → "4:59" → "4:58" etc.
- [ ] **Progress Ring**: If rendered, progress ring fills from 0% → 100% smoothly over 5 minutes.
- [ ] **No Flicker**: Updates are smooth, no flickering or jank.

### Completion
- [ ] **Timer Finishes**: After exactly 5 minutes, timer activity is replaced with "Timer Done" activity.
- [ ] **Done Message**: Activity shows "Timer Done" title and "Time's up!" message with checkmark icon.
- [ ] **System Sound**: System beep plays (NSSound.beep).
- [ ] **Auto-Dismiss**: After 3 seconds, "Timer Done" activity auto-dismisses.

### Stop Timer (Future Feature - If Implemented)
- [ ] **Menu Shows Stop**: While timer is running, menu might show "Stop Timer" option (optional for MVP).
- [ ] **Stop Works**: Click "Stop" → timer activity dismisses immediately.

## F) MENU BAR UX

### Menu Items Present
- [ ] **Toggle**: "Toggle" menu item exists and works (collapses/expands overlay).
- [ ] **Show**: "Show" menu item works (shows overlay).
- [ ] **Hide**: "Hide" menu item works (hides overlay).
- [ ] **Start Timer**: "Start Timer (5 min)" menu item exists and works.
- [ ] **Settings**: "Settings" menu item opens settings window (basic UI appears).
- [ ] **Safe Mode**: "Safe Mode" menu item toggles safe mode (logging via menu click works).
- [ ] **Quit**: "Quit" menu item closes app cleanly.

### Status Bar Icon
- [ ] **Status Item**: Small circular icon "◎" appears in menu bar.
- [ ] **Click Opens Menu**: Click status item → menu appears.
- [ ] **Click Again Toggles**: Click status item (not menu) → overlay toggles visible/hidden.

## G) LOGGING & DIAGNOSTICS

### State Transitions
- [ ] **Logged Once**: Expand overlay → "overlayMode: compact → expanded" logged once (debounced).
- [ ] **Hover Logged**: Hover over pill → "Hover detected" logged in diagnostic output.
- [ ] **Click Logged**: Click overlay → logged in output.

### Drop Events
- [ ] **Drop Logged**: Drag 3 files, drop → log shows "Tray item dropped" and item count.
- [ ] **URL Resolution**: Log shows resolved file URLs after drop.
- [ ] **App Flag**: If dropping .app, log indicates app bundle detected.

### Clipboard Events
- [ ] **Text Type Logged**: Copy text → log shows "Clipboard: text" with hash.
- [ ] **Image Type Logged**: Copy image → log shows "Clipboard: image".
- [ ] **No Duplicate Spam**: Copy same item twice → only one log entry for clipboard change.

### Idle No Spam
- [ ] **Quiet When Idle**: Let app run for 30 seconds with no activity → diagnostics log should have minimal noise (no spam).
- [ ] **Diagnostics Export**: Menu → "Copy Diagnostics" → can verify no excessive logging.

## H) PERFORMANCE & STABILITY

### Memory
- [ ] **No Leaks**: Open System Monitor → Activity tab → find "Mac灵动岛", note memory. Run for 10 minutes with drops/copies/timer, memory should not grow indefinitely.
- [ ] **Tray Limit**: Add 50+ files to tray → app doesn't crash, tray is scrollable, memory reasonable.

### CPU
- [ ] **Idle < 1%**: App not doing anything → CPU usage < 1%.
- [ ] **Timer < 5%**: During 5-minute countdown → CPU stays < 5%.

### Multi-Display
- [ ] **Main Screen**: Close laptop lid or disconnect monitor → overlay repositions to remaining active display.
- [ ] **Spaces**: Open 3 Spaces, overlay visible in Space 1 → switch to Space 2, overlay still visible (thanks to collectionBehavior).

### Focus
- [ ] **No Stealing**: Drag files onto overlay → overlay does not steal focus from active app (user can continue typing).
- [ ] **Click to Focus**: Click overlay → app becomes key (this is acceptable).
- [ ] **Hover Safe**: Hover mode does not steal focus.

## I) EDGE CASES

- [ ] **Rapid Clicks**: Click pill 10 times rapidly → no crashes, state debounced properly.
- [ ] **Drag While Timer**: While timer running, drag files → both features work together.
- [ ] **Switch Spaces Mid-Drag**: Start drag in Space 1, switch Space 2, drop → graceful handling, no crash.
- [ ] **Close and Reopen**: Close app, reopen → tray items restored, no crashes.

## J) VISUAL POLISH

- [ ] **Smooth Animations**: Expand/collapse animations are smooth (not jerky).
- [ ] **Consistent Styling**: Colors, fonts, spacing match design (ultraThinMaterial background, white borders).
- [ ] **Responsive UI**: All buttons/clicks respond immediately.
- [ ] **Text Truncation**: Long file names in tray truncated with "..." if needed.

---

## Sign-Off Checklist

If all above pass:
- [ ] Ready to ship MVP
- [ ] Ready to commit with message: "MVP complete: drag-drop, clipboard, timer, menu integration"
- [ ] Create git tag: `v0.1.0-mvp`

---

## Known Limitations (Not Required for MVP)

- No custom timer duration UI (hardcoded to 5 minutes)
- No tray persistence to disk (in-memory only per app session)
- No activity action buttons wired (dismiss/open-tray are UI stubs)
- No keyboard shortcuts beyond Escape and Option+Space
- No onboarding/tutorial (exists but basic)

