# Module C: Now Playing - Manual Test Checklist

## PREREQUISITES

1. **Apple Music installed** (comes with macOS)
2. **Spotify installed** (optional - test will indicate if fails)
3. Build and run app

---

## TEST 1: APPLE MUSIC - PLAYBACK DETECTION (30 seconds)

**Action**:
1. Open Apple Music app
2. Play any song
3. Watch notch area

**Expected within 1 second**:
- ✅ Overlay appears (if was hidden)
- ✅ Pill shows:
  - Album artwork placeholder (purple/blue gradient)
  - Track title
  - Artist name
  - Play/pause button (showing pause icon)
  - Previous/Next buttons
  - Thin progress bar at bottom
- ✅ Debug HUD shows:
  - Visibility: VISIBLE
  - Reason: nowPlaying
  - Last Event: `Now Playing: [Track Title] - [Artist]`

**Console check**:
```
⏱️ [HH:MM:SS.mmm] Now Playing: Song Title - Artist Name
🟢 AppState.showOverlay(reason: nowPlaying)
```

---

## TEST 2: PLAY/PAUSE CONTROL (10 seconds)

**Action**:
1. With music playing, click **pause button** in overlay
2. Wait 1 second
3. Click **play button** in overlay

**Expected**:
- ✅ First click: Music pauses in Apple Music app
- ✅ Button icon changes to play icon
- ✅ Second click: Music resumes
- ✅ Button icon changes back to pause icon
- ✅ Debug HUD updates isPlaying state

**CRITICAL**: If buttons don't respond, AppleScript permissions may be denied.

---

## TEST 3: NEXT TRACK (10 seconds)

**Action**:
1. With music playing, click **next button** in overlay

**Expected within 300ms**:
- ✅ Music skips to next track in Apple Music
- ✅ Overlay updates showing new track title + artist
- ✅ Progress bar resets to 0%
- ✅ Debug HUD shows new event: `Now Playing: [New Track] - [Artist]`

---

## TEST 4: PREVIOUS TRACK (10 seconds)

**Action**:
1. Click **previous button** in overlay

**Expected**:
- ✅ Music goes to previous track
- ✅ Overlay updates with new track info

---

## TEST 5: PROGRESS BAR UPDATES (20 seconds)

**Action**:
1. Watch the thin progress bar at bottom of pill
2. Let song play for 20 seconds

**Expected**:
- ✅ Progress bar advances smoothly (updates every 0.5s)
- ✅ Bar fills from left to right
- ✅ No flickering or jumpiness

---

## TEST 6: REVEAL SOURCE APP (5 seconds)

**Action**:
1. Click anywhere on the overlay pill (not on buttons)

**Expected**:
- ✅ Apple Music app comes to foreground
- ✅ Music keeps playing
- ✅ Overlay stays visible

---

## TEST 7: STOP MUSIC (10 seconds)

**Action**:
1. In Apple Music app, press stop (⏹)
2. Watch overlay

**Expected within 5 seconds**:
- ✅ Overlay disappears (auto-hides)
- ✅ Debug HUD shows: Visibility: HIDDEN
- ✅ Polling drops to 5-second interval (backoff)

---

## TEST 8: MODULE PRIORITY - NOW PLAYING vs CLIPBOARD (20 seconds)

**Action**:
1. Start music playing (overlay appears)
2. Copy any text (Cmd+C)
3. Wait 2 seconds

**Expected**:
- ✅ Overlay shows **now playing** (NOT clipboard)
- ✅ Now playing has higher priority
- ✅ Clipboard activity is ignored while music plays
- ✅ Debug HUD shows: Activities: 1 (clipboard posted but not displayed)

---

## TEST 9: MODULE PRIORITY - DRAG DROP vs NOW PLAYING (20 seconds)

**Action**:
1. Start music playing
2. Drag file onto overlay
3. Drop it

**Expected**:
- ✅ Overlay expands to panel (drag/drop has higher priority)
- ✅ Panel shows tray with dropped file
- ✅ Now playing temporarily hidden
- ✅ After 4 seconds, panel collapses
- ✅ Now playing reappears (if music still playing)

---

## TEST 10: SPOTIFY (OPTIONAL - 30 seconds)

**Action**:
1. Close Apple Music (stop playback)
2. Open Spotify
3. Play any song

**Expected**:
- ✅ Overlay appears within 1 second
- ✅ Shows Spotify track info
- ✅ Controls work (play/pause, next, previous)
- ✅ Debug HUD shows sourceApp: Spotify

**If Spotify fails**:
- Check Console for AppleScript errors
- Spotify may not support AppleScript (older versions)
- **Music is required; Spotify is optional**

---

## TEST 11: ADAPTIVE POLLING (30 seconds)

**Action**:
1. Play music
2. Watch Console for polling frequency
3. Pause music
4. Wait 10 seconds
5. Stop music
6. Wait 10 seconds

**Expected polling intervals**:
- ✅ Playing: ~0.5s (2Hz)
- ✅ Paused: ~2s (0.5Hz)
- ✅ Stopped: ~5s (backoff)

**Console pattern**:
```
[No output when idle]
[Every 0.5s when playing]
[Every 2s when paused]
[Every 5s when stopped]
```

---

## TEST 12: PERFORMANCE (CPU CHECK)

**Action**:
1. Open Activity Monitor
2. Find "Mac灵动岛" process
3. Play music for 1 minute

**Expected**:
- ✅ CPU < 3% while playing (2Hz polling)
- ✅ CPU < 1% when paused (0.5Hz polling)
- ✅ CPU < 0.5% when stopped (5s backoff)
- ✅ No memory leaks (memory stable over time)

---

## PASS CRITERIA

If ALL Music tests (1-9, 11-12) pass:
✅ Module C: Now Playing is COMPLETE for Apple Music
✅ Adaptive polling working (2Hz → 0.5Hz → backoff)
✅ Controls functional (play/pause, next, previous)
✅ Module priority correct (drag > now playing > clipboard)
✅ Performance acceptable (< 3% CPU)

**Spotify optional**: If test 10 fails, note it but don't block release.

---

## KNOWN LIMITATIONS

- **No album artwork** (NSImage fetching expensive, skipped for MVP)
- **Polling-based** (not real-time, 0.5s latency acceptable)
- **Spotify may fail** on some versions (AppleScript support varies)
- **No seek control** (scrubbing progress bar not implemented)

---

## TROUBLESHOOTING

### Overlay never shows on music play
- Check: NowPlayingManager started? Console shows polling?
- Check: Apple Music actually running and playing?
- Run AppleScript manually:
  ```bash
  osascript -e 'tell application "Music" to get name of current track'
  ```

### Buttons don't work
- Check: macOS System Preferences → Privacy & Security → Automation
- Ensure app has permission to control Music/Spotify

### Polling too slow
- Check: getPollingInterval() returning correct values?
- Check: Timer scheduling on main thread?

### CPU too high
- Check: Polling never exceeds 2Hz (0.5s minimum interval)?
- Check: AppleScript execution on background queue?

---

## TOTAL TIME: ~3 minutes

