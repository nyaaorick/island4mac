# Clipboard Memory - Refined 4-State Checklist

## Philosophy Check (CRITICAL)
Before testing, answer these:
- [ ] Does it feel like a clipboard manager? **→ FAIL**
- [ ] Does it feel like macOS compensating for forgetfulness? **→ PASS**
- [ ] Can you "manage" clipboard items? **→ FAIL**
- [ ] Does it just remember briefly then get out of the way? **→ PASS**

---

## State 1: Silent (Default)
- [ ] Island is visible but shows only minimal idle state
- [ ] No clipboard UI visible
- [ ] CPU usage near 0% in Activity Monitor

**Expected**: Completely calm, no attention cost

---

## State 2: Copy Confirmation
### Trigger: Copy any text (⌘C)
- [ ] Island shows "已复制" + preview immediately
- [ ] Preview is single-line, fade-truncated at ~50 chars
- [ ] No line breaks visible in preview
- [ ] Toast auto-dismisses in ~1 second
- [ ] NO bounce, NO elastic motion — just settle

### Content Intelligence
- [ ] Copy code → shows monospaced preview
- [ ] Copy URL → shows link icon
- [ ] Copy same text twice → updates timestamp only (no duplicate)
- [ ] Copy URL with `?utm_source=...` → strips tracking params internally

**Expected**: Calm confirmation, not celebration

---

## State 3: Intent Peek
### Trigger: Click island DURING toast (within 2s of copy)
- [ ] Island expands slightly
- [ ] Shows 2-3 most recent items ONLY
- [ ] NO header text
- [ ] NO scroll (all items visible)
- [ ] Most recent item has medium weight
- [ ] Older items fade to lower opacity

### Select Item
- [ ] Click item → restores to clipboard
- [ ] Picker closes immediately (no pin needed)
- [ ] Island returns to Silent state

**Expected**: Quick peek, not a full list

---

## State 4: Focused Recall
### Trigger A: Menu item "打开剪贴板历史"
- [ ] Island expands
- [ ] Shows up to 6-8 items
- [ ] Header shows "剪贴板" (quieter title)
- [ ] Pin and Clear buttons visible
- [ ] Scrollable if >6 items

### Trigger B: Hotkey ⌥⌘V
- [ ] Same as menu trigger
- [ ] Works even if >2s since last copy
- [ ] Opens Focused Recall, not Intent Peek

### Visual Hierarchy
- [ ] Most recent item: medium weight, 0.75 opacity
- [ ] Older items: regular weight, 0.55 opacity
- [ ] Icons fade progressively
- [ ] Code items show monospaced font

### Interactions
- [ ] Select item → restores to clipboard
- [ ] If NOT pinned → picker closes
- [ ] If pinned → picker stays open
- [ ] Clear button → empties all, closes picker

**Expected**: Still restrained, not a power tool

---

## Intelligence Tests
### Deduplication
- [ ] Copy "Hello World"
- [ ] Copy "Hello World" again
- [ ] Only 1 item in history (timestamp updated)

### URL Normalization
- [ ] Copy `https://example.com?utm_source=twitter&id=123`
- [ ] Copy `https://example.com?id=123`
- [ ] Treated as same URL (tracking params stripped)

### Code Detection
- [ ] Copy `function test() { return true; }`
- [ ] Item shows code icon + monospaced preview

---

## Motion & Performance
- [ ] Toast appears: no bounce, just settle
- [ ] Picker expands: gentle ease-out (0.25s)
- [ ] Picker collapses: feels inevitable, not triggered
- [ ] NO elastic overshoot anywhere
- [ ] CPU idle: < 0.5% (0.5s polling interval)

---

## Expiration
- [ ] Items expire after 24 hours (not 5 minutes)
- [ ] Expiration happens silently (no notification)
- [ ] Console shows NO expiration logs in release build

---

## Edge Cases
- [ ] Copy empty string → nothing happens
- [ ] Copy whitespace-only → nothing happens
- [ ] Open picker with empty history → picker doesn't open
- [ ] Hotkey when history empty → no action
- [ ] Menu item when history empty → no action (not greyed)

---

## Final Quality Bar

### ✅ PASS Criteria
- Feels like "macOS remembering what I just copied"
- Never feel like I'm "managing" clipboard
- Motion is calm, confident, restrained
- Copy → confirm → disappear is smooth and inevitable
- Intent Peek feels like a quick glance
- Focused Recall feels like a calm archive, not a power tool
- Zero CPU cost when idle
- All logging gated behind `#if DEBUG`

### ❌ FAIL Criteria
- Feels like a clipboard manager app
- Feels like a productivity tool
- Any aggressive motion or bounce
- User thinks "how do I configure this?"
- Toast feels attention-seeking
- Picker feels like a separate feature

---

## Console Validation (DEBUG builds only)
- [ ] Copy text → `[ClipboardHistory] Added text (total: N)`
- [ ] Open picker → no logs
- [ ] Select item → `[ClipboardHistory] Restored item`
- [ ] Clear all → `[ClipboardHistory] Cleared all`
- [ ] Menu action → `[StatusBarController] ✅ ACTION: ...`

## Console Validation (RELEASE builds)
- [ ] NO clipboard logs visible
- [ ] NO status bar logs visible
- [ ] Silent operation

---

## Philosophical Alignment Check

Ask yourself after testing:
1. "Did I ever feel like I was using a feature?"
   - **NO** → ✅ Success
   - **YES** → ❌ Too prominent

2. "Did I forget the clipboard UI was there?"
   - **YES** → ✅ Success  
   - **NO** → ❌ Too attention-seeking

3. "Would I miss this if it was gone?"
   - **YES, but I can't explain why** → ✅ Perfect
   - **NO** → ❌ Not useful enough
   - **YES, I use it all the time** → ❌ Too power-user

---

## Sign-Off

- [ ] All technical tests pass
- [ ] Motion feels calm and inevitable
- [ ] CPU usage negligible
- [ ] Philosophy alignment confirmed
- [ ] Ready for daily use

**Quality Standard**: "A missing macOS capability, gently restored."
