# CLAUDE.md

macOS menu bar app (Swift, SwiftUI + AppKit) that turns the MacBook notch into a "Dynamic Island": now playing with lyrics, coding-agent progress (Claude Code, Codex, ZCode), clipboard history and a drag-and-drop file shelf. Based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Rules for this repo

- English only: code, comments, log messages, UI strings and test fixtures. The only localization is `en.lproj/Localizable.strings` (read through `L("key")` in `Utilities/Localization.swift`).
- Swift only: no C, Objective-C or shell files, including the two helpers (`ClaudeHookBridge/main.swift`, `MediaRemoteAdapter/MediaRemoteAdapter.swift`). The hook helper runs on every agent hook event, so keep it to `import Darwin` and check its startup time (about 27 ms per run, same as the old C version) after changing it.
- Docs are limited to this file, `roadmap.md` and `backup.md`. Do not add a `docs/` folder or a README.
- The app is not sandboxed (MediaRemote and AppleScript need that). Distribution is Developer ID + notarization, outside the Mac App Store.

## Build and test

<!-- AUTO-GENERATED from MacDynamicIsland.xcodeproj -->

| Command | Description |
|---|---|
| `open MacDynamicIsland.xcodeproj` | Open in Xcode (scheme `MacDynamicIsland`, pick a team under Signing & Capabilities) |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' build` | Build |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' test` | Run unit tests |

<!-- END AUTO-GENERATED -->

- Deployment target is macOS 26.0.
- Tests (`MacDynamicIslandTests`) are hosted by the app. When running as a test host the app skips launch setup (hotkeys, clipboard polling, menu bar item, music module).
- Bundle id: `com.macdynamicisland.app`. Product name: `MacDynamicIsland`.

## Layout

```text
MacDynamicIsland/     App entry (MacDynamicIslandApp.swift), Info.plist, entitlements, assets
AppDelegate.swift     App delegate and AppIntegration (starts background managers)
Controllers/          OverlayWindowController + IslandWindow (the island panel), StatusBarController
State/                AppState (shared UI state), interaction/visibility enums
Views/                NotchHomeView (root view, NotchMetrics), Music, Clipboard, Shelf, Agents, Settings tabs
Settings/             Settings window controller, clipboard settings tab
Music/                MusicManager: playback state, controls, artwork, lyrics
Services/             NowPlayingManager (MediaRemote via adapter), LyricsService, clipboard store, shelf persistence, thumbnails, Quick Look
Managers/             Clipboard polling, hotkeys, drag detection, screens, full-screen video detection
Agents/               Hook events, socket server, session store, hook installer, terminal focusing
ClaudeHookBridge/     island-claude-hook: the command every agent's hooks run
MediaRemoteAdapter/   Library loaded into perl by the now-playing helper process (exports mediaremote_adapter_stream)
Models/, ViewModels/, Utilities/, Extensions/, Animations/, Configuration/, Protocols/
en.lproj/             Localizable.strings
```

## How it starts

`MacDynamicIslandApp` (@main) has an empty Settings scene; `AppDelegate.applicationDidFinishLaunching` creates `OverlayWindowController.shared` (borderless panel hosting `NotchHomeView`, owns `AppState` and `NowPlayingManager` -> `MusicManager`), `AppIntegration.start()` (ClipboardManager, HotKeyManager) and `StatusBarController`.

## Things that are easy to break

- Since macOS 15.4 mediaremoted only answers Apple-signed processes, so now-playing is read by running `/usr/bin/perl` with `libMediaRemoteAdapter.dylib` and parsing JSON lines. Playback commands go direct.
- Island animation is driven entirely by SwiftUI springs; the panel (`IslandWindow`) is only a viewfinder that grows before expanding and shrinks after the spring settles. Don't add AppKit animation or let SwiftUI content constrain the window (AutoLayout <-> setFrame recursion).
- `@Published` fires at willSet; panel sizing therefore reacts in didSet or on the next runloop turn.
- Agent hooks: connecting adds one command hook per event to the agent's config (Claude Code `~/.claude/settings.json`, Codex `~/.codex/hooks.json`, ZCode `~/.zcode/cli/config.json`), backed up to `<file>.mac-island-backup`. The helper talks to the app over a per-user Unix socket, prints nothing and always exits 0. Claude Code's `PermissionRequest` hook runs in the foreground (`claude wait`) so the island can answer questions.
- Permissions: Accessibility (hotkeys, full-screen detection on the built-in display), Automation/Apple Events (Music lyrics, paste via System Events, terminal tab focus).
- Shortcuts: ⇧⌘Space toggle, ⌥⌘Space show/hide, ⌥⌘V clipboard tab.
