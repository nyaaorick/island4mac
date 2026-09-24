# Mac灵动岛 (Mac Dynamic Island)

A macOS menu bar app that turns the area around the MacBook notch into an interactive "Dynamic Island": now playing with lyrics, Claude Code progress, clipboard history and a drag-and-drop file shelf. It is based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Features

- **Now playing**: track, artwork, playback controls and synced lyrics, both in the collapsed island and in the Music tab. It shows whatever the system Now Playing shows in Control Center (Apple Music, Spotify, browser audio and video, video players), read through the MediaRemote framework. Apple Music lyrics come from AppleScript, and lyrics are also looked up on NetEase Cloud Music and LRCLIB.
- **Claude Code**: while a session works, waits for your permission or has just finished, the collapsed island shows its status left of the notch and its progress (tasks done, or elapsed time) to the right. The Agents tab lists every session with what it's doing, its task progress and a button that brings its Terminal or iTerm2 tab to the front. Connect it in Settings → Claude Code; see "How Claude Code is connected" below.
- **Clipboard**: text, links, code and images you copy are kept (50 items for 24 hours by default), can be searched and filtered, and can be pasted back into the frontmost app.
- **Files shelf**: drag files onto the notch to park them. The shelf keeps security-scoped bookmarks and shows thumbnails and Quick Look previews.
- **Menu bar item** to show or hide the island, open Settings and quit.

## Requirements

- macOS 27 or later. The island sits under the notch on MacBooks that have one and at the top center of other screens.
- With several displays, the island follows the mouse to whichever display it's on (Settings → General → 自动切换显示器). With that off it stays on the built-in display.
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
| Accessibility | Global keyboard shortcuts. Settings → General has a button to request it. |
| Automation (Apple Events) | Reading lyrics from Music, pasting clipboard items through System Events, and selecting a Claude Code session's tab in Terminal or iTerm2. |

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
Agents/               Claude Code: hook events, the socket server, the session store, the hook installer, terminal focusing
ClaudeHookBridge/     island-claude-hook, the command Claude Code's hooks run
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

## How Claude Code is connected

Connecting adds one command hook to each Claude Code hook event in `~/.claude/settings.json` (the file is backed up to `settings.json.mac-island-backup` the first time), next to any hooks already there. The command runs `island-claude-hook`, copied to `~/Library/Application Support/com.macdynamicisland.app/`, in the background (`"async": true`) so it never slows Claude Code down. The helper forwards the event JSON, plus the terminal the session runs in, to the app over a Unix socket only your user can open. It prints nothing and always exits 0, so Claude Code carries on normally when the island isn't running. Disconnecting removes only these entries.

## Known limitations

- Since macOS 15.4, mediaremoted only answers now-playing reads from Apple-signed processes. The app therefore runs `/usr/bin/perl` as a helper that loads `libMediaRemoteAdapter.dylib` (built from `MediaRemoteAdapter/`) and streams the now-playing state back as JSON lines, the same approach as boring.notch's mediaremote-adapter. Playback commands are still sent directly. If Apple closes this path, the island will stop showing now playing.
- Apps that don't report to the system Now Playing (nothing shows in Control Center) aren't shown.
- The AppIcon set has no images yet.
- Some settings aren't wired up yet and have no effect: the menu bar icon, shadow, lighting effect, gradient, colored spectrogram, music control slot limit and slider color toggles; the shelf on/off toggle; the three gesture settings; showing on all displays and the display picker; expanded drag detection; the settings icon in the notch; the idle face; notch height; and remembering the last tab.
- ⌥⌘L (position lock) and ⌥⌘M (move mode) are registered, but nothing reads the flags they toggle yet.

## License

No license file has been added yet. The project is derived from boring.notch, so check boring.notch's license terms before choosing one.
