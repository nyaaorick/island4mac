# Clipboard Memory - Manual Test Checklist

## Prerequisites
- Build and run the app in Xcode
- Open Console.app and filter for "Clipboard" to see logs

## Test 1: Toast Appears on Copy
- [ ] Select any text in another app (e.g. Safari)
- [ ] Press ⌘C to copy
- [ ] **EXPECTED**: Island shows "已复制" + preview for ~1.2s
- [ ] **EXPECTED**: Console shows `[ClipboardHistory] Added item`
- [ ] **EXPECTED**: Toast auto-dismisses after 1.2s

## Test 2: Click Toast to Open Picker
- [ ] Copy some text (⌘C)
- [ ] While toast is visible, click the island
- [ ] **EXPECTED**: Island expands to show clipboard history list
- [ ] **EXPECTED**: List shows the item you just copied

## Test 3: Select Item from Picker
- [ ] Copy 3 different text snippets
- [ ] Open picker (click toast or use menu)
- [ ] Click on the 2nd item in the list
- [ ] **EXPECTED**: That item is restored to clipboard
- [ ] **EXPECTED**: Console shows `[ClipboardHistory] Restored item`
- [ ] Press ⌘V in TextEdit to verify it pastes correctly

## Test 4: Menu Hotkey (⌥⌘V)
- [ ] Copy some text
- [ ] Press ⌥⌘V (Option+Command+V)
- [ ] **EXPECTED**: Picker opens immediately
- [ ] **EXPECTED**: Console shows `✅ ACTION: onShowClipboardHistory`

## Test 5: Pin Button
- [ ] Open clipboard picker
- [ ] Click the pin icon (top-right)
- [ ] **EXPECTED**: Pin icon fills (becomes solid)
- [ ] Click an item to select it
- [ ] **EXPECTED**: Picker stays open (doesn't close)
- [ ] Click pin again to unpin
- [ ] Click an item
- [ ] **EXPECTED**: Picker closes after selection

## Test 6: Clear Button
- [ ] Open clipboard picker (should have items)
- [ ] Click the trash icon
- [ ] **EXPECTED**: All items cleared
- [ ] **EXPECTED**: Picker closes
- [ ] **EXPECTED**: Console shows `[ClipboardHistory] Cleared all items`

## Test 7: Menu "清空剪贴板历史"
- [ ] Copy some text
- [ ] Open status bar menu (click ◎)
- [ ] Click "清空剪贴板历史"
- [ ] **EXPECTED**: Console shows `✅ ACTION: onClearClipboardHistory`
- [ ] **EXPECTED**: Console shows `[ClipboardHistory] Cleared all items`
- [ ] Copy new text and open picker
- [ ] **EXPECTED**: Only 1 item (the new one)

## Test 8: Deduplication
- [ ] Copy text "Hello World"
- [ ] Copy "Hello World" again (same text)
- [ ] Open picker
- [ ] **EXPECTED**: Only 1 item shown (not duplicated)

## Test 9: URL Detection
- [ ] Copy a URL from Safari's address bar
- [ ] Open picker
- [ ] **EXPECTED**: Item shows with link icon (not text icon)

## Test 10: CPU Idle Test
- [ ] Let app run for 2 minutes without copying anything
- [ ] Open Activity Monitor
- [ ] Find the app process
- [ ] **EXPECTED**: CPU usage near 0% (should be < 0.5%)

## Test 11: Toast Priority
- [ ] Start playing music (to activate Now Playing)
- [ ] Copy some text
- [ ] **EXPECTED**: Clipboard toast takes priority over Now Playing in compact state

## Test 12: Expiration (5 minutes)
- [ ] Copy some text
- [ ] Wait 5 minutes (or adjust `expirationInterval` in code to 30s for testing)
- [ ] Open picker
- [ ] **EXPECTED**: Old items are removed

## Pass Criteria
- All checkboxes must be checked ✅
- No console errors or crashes
- CPU idle stays low
- All menu items work (not greyed out)
- Logs appear in Console.app for all actions

## Known Limitations (By Design)
- Max 8 items shown in picker (20 stored internally)
- Only text and URLs supported (not images/files)
- History cleared on app quit (session-based)
- Toast timeout is fixed at 1.2s
