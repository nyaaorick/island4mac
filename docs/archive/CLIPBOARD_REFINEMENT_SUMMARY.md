# Clipboard Memory - Refinement Summary

## Product Philosophy (Non-Negotiable)

**Problem Statement**: macOS forgets what I just copied.

**Solution**: The Dynamic Island briefly remembers, gently reminds, then gets out of the way.

**Anti-Pattern**: This is NOT a clipboard manager. If users feel they are "managing" clipboard, we failed.

---

## 4-State Interaction Model

```
Silent (default)
    ↓ (clipboard change)
Copy Confirmation (~1s toast)
    ↓ (click/⌥⌘V within 2s)
Intent Peek (2-3 items)
    ↓ (select/timeout)
Silent

Silent
    ↓ (⌥⌘V after 2s / menu)
Focused Recall (6-8 items)
    ↓ (select/close)
Silent
```

### State Definitions

1. **Silent**: Default, no UI, zero attention
2. **Copy Confirmation**: 1s toast showing "已复制" + preview
3. **Intent Peek**: Triggered within 2s of copy, shows 2-3 items, no scroll
4. **Focused Recall**: Triggered via menu/hotkey, shows 6-8 items, scrollable

---

## Code Architecture

### New Files Created

#### `Services/ClipboardHistoryStore.swift`
**Role**: ObservableObject managing clipboard state and history

**Key Properties**:
- `items: [ClipboardItem]` - stored history (max 20)
- `isShowingToast: Bool` - Copy Confirmation state
- `isShowingPicker: Bool` - Intent Peek / Focused Recall state
- `pickerMode: PickerMode` - `.intentPeek` or `.focusedRecall`
- `isPinned: Bool` - keeps picker open

**ClipboardItem Model**:
```swift
struct ClipboardItem {
    let content: String
    let type: ItemType  // .text, .url, .code
    let timestamp: Date
    
    var preview: String  // smart: strips newlines, caps at 50 chars
    var normalizedContent: String  // strips URL tracking params
}
```

**Key Methods**:
- `addItem(content:type:)` - semantic deduplication via `normalizedContent`
- `showPicker()` - auto-detects mode based on `isInIntentWindow` (2s)
- `showPickerExplicit(mode:)` - forces Focused Recall for menu/hotkey
- `restoreItem(_:)` - writes back to NSPasteboard
- `checkExpiration()` - removes items older than 24h

**Intelligence**:
- **Deduplication**: Same content → update timestamp only
- **URL normalization**: Strips `utm_source`, `fbclid`, etc.
- **Code detection**: Heuristic via brackets/keywords

---

#### `Services/ClipboardMonitor.swift`
**Role**: Lightweight polling monitor (0.5s interval)

**Implementation**:
- Polls `NSPasteboard.general.changeCount` every 0.5s
- Extracts content only on change
- Detects type: URL > code > text (priority order)
- Checks expiration every ~10 ticks (5s) to reduce overhead
- All logs gated behind `#if DEBUG`

**Performance**:
- Zero CPU cost when clipboard unchanged
- No busy logging in release builds

---

#### `Views/ClipboardIslandViews.swift`
**Role**: SwiftUI views for clipboard states

**Components**:
1. `ClipboardToastView` (Copy Confirmation)
   - Shows icon + "已复制" + preview
   - No animation (just appear and settle)
   - Reduced contrast (0.7 / 0.4 opacity)

2. `ClipboardPickerView` (Intent Peek / Focused Recall)
   - Mode-aware layout:
     - Intent Peek: no header, 2-3 items, no scroll
     - Focused Recall: header + pin/clear, 6-8 items, scrollable
   - Settle animation only (0.25s ease-out)

3. `ClipboardItemRow`
   - Visual hierarchy: recent item emphasized (medium weight, 0.75 opacity)
   - Code items use monospaced font
   - Hover feedback (0.06 opacity)

**Design Principles**:
- No bounce, no elastic overshoot
- Expansion feels like "content becoming available"
- Collapse feels inevitable, not triggered

---

### Modified Files

#### `Views/ NotchOverlayView.swift`
**Changes**:
- `compactContent`: Priority 1 = Clipboard Toast (tappable)
- Toast tap gesture triggers Intent Peek
- `expandedContent`: Shows `ClipboardPickerView` if `isShowingPicker`
- Injects `@EnvironmentObject clipboardStore`

#### ` Controllers/StatusBarController.swift`
**Changes**:
- Menu item: "打开剪贴板历史" (⌥⌘V) → `onShowClipboardHistory`
- Menu item: "清空剪贴板历史" → `onClearClipboardHistory`
- Both trigger `showPickerExplicit(mode: .focusedRecall)`
- Logs gated behind `#if DEBUG`

#### `Managers/HotKeyManager.swift`
**Changes**:
- Added `clipboardMonitor` for ⌥⌘V (keyCode 9)
- `handleClipboardHotkey()` → triggers Focused Recall
- Updated comments to document all 3 hotkeys

#### `State/OverlayVisibilityReason.swift`
**Changes**:
- Added `.clipboardHistory` case
- Updated `shouldAutoHide` to exclude clipboard picker

#### `State/AppState.swift`
**Changes**:
- Added `let clipboardHistory = ClipboardHistoryStore()`

#### `AppDelegate.swift`
**Changes**:
- Added `private var clipboardMonitor: ClipboardMonitor!`
- Started monitor in `applicationDidFinishLaunching`
- Stopped monitor in `applicationWillTerminate`

#### ` Controllers/ OverlayWindowController.swift`
**Changes**:
- Added `.environmentObject(appState.clipboardHistory)` to view

---

## Design Refinements

### Typography
- Copy Confirmation: medium weight, 0.7 / 0.4 opacity
- Intent Peek: no header, recent item emphasized
- Focused Recall: quieter header "剪贴板" (not "剪贴板历史")
- Code items: SF Mono font

### Motion
- Toast: no animation, just appear
- Picker expand: 0.25s ease-out (no spring)
- Hover: 0.12s ease-out
- NO bounce, NO elastic, NO celebration

### Spacing
- Tight, deliberate (6pt / 3pt vertical spacing)
- No empty list feeling
- Corner radius: 4pt (not 5pt)

### Colors
- Reduced contrast across the board
- Recent item: 0.75 opacity
- Older items: 0.55 opacity
- Icons: 0.45 → 0.35 fade

---

## Clipboard Intelligence

### Deduplication Algorithm
```swift
if mostRecent.normalizedContent == newItem.normalizedContent {
    // Update timestamp only, don't insert duplicate
    items[0] = ClipboardItem(content: trimmed, type: type, timestamp: Date())
    return
}
```

### URL Normalization
```swift
// Strip tracking params: utm_*, fbclid, gclid
components.queryItems = components.queryItems?.filter { item in
    let trackingParams = ["utm_source", "utm_medium", "utm_campaign", 
                          "utm_term", "utm_content", "fbclid", "gclid"]
    return !trackingParams.contains(item.name.lowercased())
}
```

### Code Detection
```swift
let codeIndicators = ["{", "}", "[", "]", ";", "function", "def ", 
                      "class ", "import", "const ", "let ", "var "]
if codeIndicators.contains(where: { trimmed.contains($0) }) {
    return (trimmed, .code)
}
```

---

## History Policy

- **Max stored**: 20 items internally
- **Max displayed**: 8 items (Intent Peek: 3)
- **Expiration**: 24 hours (not 5 minutes)
- **Persistence**: Session-based (cleared on app quit)

---

## Performance Guarantees

- **Polling interval**: 0.5s (not 0.4s)
- **Expiration check**: Every ~10 ticks (5s)
- **CPU idle**: < 0.5%
- **No logging**: All NSLog gated behind `#if DEBUG`
- **No allocations**: Clipboard check is just integer comparison when unchanged

---

## Menu & Keyboard Integration

### Menu Items
- "打开剪贴板历史" (⌥⌘V) → always shows Focused Recall
- "清空剪贴板历史" → empties all, closes picker
- Both have explicit `target = self`
- Both always enabled (never greyed)

### Hotkeys
- **⌘⇧Space**: Toggle overlay (primary)
- **⌘⌥Space**: Force close overlay (secondary)
- **⌘⌥V**: Open Focused Recall (clipboard)

---

## Testing Strategy

### Unit Tests (Not Implemented Yet)
- ClipboardItem.normalizedContent with various URLs
- Deduplication logic with identical/similar content
- Code detection heuristic

### Manual Testing
See `CLIPBOARD_REFINED_CHECKLIST.md` for comprehensive checklist

### Quality Bar
- **PASS**: Feels like "macOS remembering what I just copied"
- **FAIL**: Feels like a clipboard manager app

---

## Future Considerations (Out of Scope)

**DO NOT ADD** unless explicitly requested:
- Image/file clipboard support
- Clipboard search
- Clipboard sync across devices
- Clipboard categories/tags
- Configurable expiration
- Persistent storage across app restarts
- Statistics/analytics

**Reason**: These turn it into a clipboard manager, which violates the product philosophy.

---

## Release Checklist

- [ ] All `NSLog` statements gated behind `#if DEBUG`
- [ ] No console spam in release builds
- [ ] CPU idle < 0.5% confirmed in Activity Monitor
- [ ] 4-state interaction model working correctly
- [ ] ⌥⌘V hotkey functional
- [ ] Menu items functional
- [ ] Motion feels calm (no bounce)
- [ ] Deduplication working (same content → timestamp update)
- [ ] URL normalization working (tracking params stripped)
- [ ] Code detection working (monospaced preview)
- [ ] 24h expiration working (silent cleanup)
- [ ] Philosophy alignment confirmed

---

## Sign-Off

**Quality Standard**: "A missing macOS capability, gently restored."

If users say "I didn't notice it until it saved me" → **SUCCESS**  
If users say "This is a great clipboard manager!" → **FAILURE**
