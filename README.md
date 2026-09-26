# Mac灵动岛 (Mac Dynamic Island)

A macOS menu bar app that turns the area around the MacBook notch into an interactive "Dynamic Island": now playing with lyrics, coding agent progress (Claude Code, Codex, ZCode), clipboard history and a drag-and-drop file shelf. It is based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Features

- **Now playing**: track, artwork, playback controls and synced lyrics, both in the collapsed island and in the Music tab. It shows whatever the system Now Playing shows in Control Center (Apple Music, Spotify, browser audio and video, video players), read through the MediaRemote framework. Apple Music lyrics come from AppleScript, and lyrics are also looked up on NetEase Cloud Music and LRCLIB.
- **Coding agents** (Claude Code, Codex, ZCode): while a session works, waits for your permission or has just finished, the collapsed island shows its status and progress (tasks done, or elapsed time) beside the notch. The Agents tab lists every session with its agent, what it's doing, its task progress and a button that brings its Terminal or iTerm2 tab (or the agent's app) to the front. When Claude asks you a question (AskUserQuestion) or asks to use a tool, the island opens on it. You can answer, allow, always allow or deny right there, or still answer in the terminal. Connect each agent in Settings → Agents; see "How agents are connected" below.
- **Clipboard**: text, links, code and images you copy are kept (50 items for 24 hours by default), can be searched and filtered, and can be pasted back into the frontmost app.
- **Files shelf**: drag files onto the notch to park them. The shelf keeps security-scoped bookmarks and shows thumbnails and Quick Look previews.
- **Menu bar item** to show or hide the island, open Settings and quit.

## Requirements

- macOS 27 or later. The island sits under the notch on MacBooks that have one and at the top center of other screens.
- With several displays, the island follows the mouse to whichever display it's on (Settings → General → 自动切换显示器). With that off it stays on the built-in display.
- On an external display at least 1920 points wide the island is wider: it opens 760 points wide instead of 640, and while it shows now playing or an agent session the collapsed pill widens from 185 to 360 points, enough for the whole title and lyric line, or for what the agent is doing. The built-in display keeps its island as it is.
- While the app that's playing (the one Now Playing shows: a video player, or the browser a web video plays in) is in full screen, the island on that display hides until it leaves full screen (Settings → General → 全屏看视频时隐藏). Other full-screen apps, like a terminal or an editor, keep the island. On the built-in display the island needs Accessibility permission to tell full screen from a window that's merely as large.
- Xcode 27 or later to build.

## Build and run

Open the project, select the `Mac灵动岛` scheme, pick your team under Signing & Capabilities, and run:

```bash
open Mac灵动岛.xcodeproj
```

From the command line:

```bash
xcodebuild -project Mac灵动岛.xcodeproj -scheme Mac灵动岛 -destination 'platform=macOS' build
```

```bash
xcodebuild -project Mac灵动岛.xcodeproj -scheme Mac灵动岛 -destination 'platform=macOS' test
```

`build_test.sh` runs a clean Debug build and reports the warning count.

The unit tests in `Mac灵动岛Tests` are hosted by the app. When it runs as a test host, the app skips its launch setup (hotkeys, clipboard polling and the menu bar item).

## Permissions

| Permission | Used for |
|---|---|
| Accessibility | Global keyboard shortcuts, and telling a video in full screen on the built-in display from a window that's merely as large. Settings → General has a button to request it. |
| Automation (Apple Events) | Reading lyrics from Music, pasting clipboard items through System Events, and selecting an agent session's tab in Terminal or iTerm2. |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⇧⌘Space | Expand or collapse the island |
| ⌥⌘Space | Show or hide the island |
| ⌥⌘V | Open the island on the clipboard tab |

## Distribution

The app ships outside the Mac App Store. It is not sandboxed, because the MediaRemote framework and AppleScript control of other apps don't work in the sandbox. Sign it with a Developer ID certificate (Hardened Runtime is on) and notarize it. The only entitlement is Apple Events.

## Project layout

```text
Mac灵动岛/            App entry point (Mac灵动岛App.swift), Info.plist, entitlements, asset catalog
AppDelegate.swift     App delegate and AppIntegration, which starts the background managers
Controllers/          OverlayWindowController (the island panel) and StatusBarController (menu bar item)
State/                AppState, the shared UI state, plus interaction and visibility enums
Views/                NotchHomeView (root view, and NotchMetrics with each tab's open size) and the Music, Clipboard and Shelf views
Views/Settings/       Settings tabs
Settings/             Settings window controller and the clipboard settings tab
Music/                MusicManager: playback state, controls, artwork and lyrics
Services/             Now playing (MediaRemote via the adapter), lyrics, clipboard store, shelf persistence, thumbnails, Quick Look
Managers/             Clipboard polling, global hotkeys, drag detection, screens, analytics
Models/, ViewModels/  Now playing and shelf models and the shelf view model
Utilities/            Settings store (Defaults+Keys.swift), AppleScript, localization, logging and other helpers
Extensions/           Small AppKit and SwiftUI extensions
MediaRemoteAdapter/   Library the now-playing helper process loads (see below)
Agents/               Coding agents: hook events, the socket server, the session store, the hook installer, session titles, terminal focusing
ClaudeHookBridge/     island-claude-hook, the command every agent's hooks run
Mac灵动岛Tests/        Unit tests
docs/archive/         Notes from earlier development; kept for reference and mostly out of date
```

## How it starts

```text
Mac灵动岛App (@main)
├─ Settings scene → MainSettingsView
└─ AppDelegate.applicationDidFinishLaunching
   ├─ OverlayWindowController.shared   borderless panel at the notch hosting NotchHomeView
   │  ├─ AppState                       loads clipboard history, starts global drag detection
   │  └─ NowPlayingManager → MusicManager
   ├─ AppIntegration.start()            ClipboardManager, HotKeyManager
   └─ StatusBarController               menu bar item
```

## How agents are connected

Claude Code, Codex and ZCode all run command hooks with Claude Code's JSON input. Connecting an agent adds one command hook to each hook event it supports, next to any hooks already there, in its config file (backed up to `<file>.mac-island-backup` the first time):

| Agent | Config file | Notes |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | Runs in the background (`"async": true`) so it never slows Claude Code down. |
| Codex | `~/.codex/hooks.json` | Codex runs a new hook only after you trust it: run `/hooks` in Codex after connecting. `update_plan` shows as the task list. |
| ZCode | `~/.zcode/cli/config.json` (`hooks.events`) | Also sets `hooks.enabled`, since ZCode ignores config-file hooks otherwise. ZCode has no session-end event, so its sessions leave the list when ZCode quits or after 12 quiet hours. |

The command runs `island-claude-hook`, copied to `~/Library/Application Support/com.macdynamicisland.app/`, with the agent's name as an argument. The helper forwards the event JSON, plus the agent and the terminal the session runs in, to the app over a Unix socket only your user can open. It prints nothing and always exits 0, so the agent carries on normally when the island isn't running. Disconnecting removes only these entries.

Claude Code's `PermissionRequest` hook is the exception: it runs in the foreground (`island-claude-hook … claude wait`, with a 24-hour timeout) so the island can answer Claude's questions. Claude Code shows its own prompt at the same time and takes whichever answer comes first. The island keeps the connection open while its card is up, and replies with a `PermissionRequest` decision:

- A question: allow the AskUserQuestion call with your `answers` filled in.
- Allow: allow the call.
- Always allow: allow it and pass Claude Code's `permission_suggestions` back as `updatedPermissions`, like "don't ask again" in the terminal.
- Deny: deny with `interrupt`, which stops the turn like Esc. If you write a note first, Claude carries on with the note instead.

Once the call is answered in the terminal (the island matches its `PostToolUse` by tool input) or the turn ends, the island closes the connection without a reply, so the hook changes nothing.

## Known limitations

- Since macOS 15.4, mediaremoted only answers now-playing reads from Apple-signed processes. The app therefore runs `/usr/bin/perl` as a helper that loads `libMediaRemoteAdapter.dylib` (built from `MediaRemoteAdapter/`) and streams the now-playing state back as JSON lines, the same approach as boring.notch's mediaremote-adapter. Playback commands are still sent directly. If Apple closes this path, the island will stop showing now playing.
- Apps that don't report to the system Now Playing (nothing shows in Control Center) aren't shown.
- The AppIcon set has no images yet.
- Some settings aren't wired up yet and have no effect: the menu bar icon, shadow, lighting effect, gradient, colored spectrogram, music control slot limit and slider color toggles; the shelf on/off toggle; the three gesture settings; showing on all displays and the display picker; expanded drag detection; the settings icon in the notch; the idle face; notch height; and remembering the last tab.

## License

No license file has been added yet. The project is derived from boring.notch, so check boring.notch's license terms before choosing one.
