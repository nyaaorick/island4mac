# CLAUDE.md

macOS menu bar app (Swift, SwiftUI + AppKit) that turns the MacBook notch into a "Dynamic Island": now playing with lyrics, coding-agent progress (Claude Code, Codex, ZCode), clipboard history and a drag-and-drop file shelf. Based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Rules for this repo

- English only: code, comments, log messages, UI strings and test fixtures. The only localization is `MacDynamicIsland/Resources/en.lproj/Localizable.strings` (read through `L("key")` in `Shared/Utilities/Localization.swift`).
- Swift only: no C, Objective-C or shell files, including the two helpers (`Helpers/ClaudeHookBridge/main.swift`, `Helpers/MediaRemoteAdapter/MediaRemoteAdapter.swift`). The hook helper runs on every agent hook event, so keep it to `import Darwin` and check its startup time (about 27 ms per run, same as the old C version) after changing it.
- Docs are limited to this file, `README.md`, `roadmap.md` and `backup.md`. Do not add a `docs/` folder. Keep the README short.
- The app is not sandboxed (MediaRemote and AppleScript need that). Distribution is Developer ID + notarization, outside the Mac App Store.

## Build and test

<!-- AUTO-GENERATED from MacDynamicIsland.xcodeproj -->

| Command | Description |
|---|---|
| `open MacDynamicIsland.xcodeproj` | Open in Xcode (scheme `MacDynamicIsland`, pick a team under Signing & Capabilities) |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' build` | Build |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' test` | Run unit tests |

<!-- END AUTO-GENERATED -->

- `Launch.command` (double-click in Finder) builds into `build/` and opens the app. It is a Swift script (`#!/usr/bin/env swift`), not shell.
- Deployment target is macOS 26.0.
- Tests (`MacDynamicIslandTests`) are hosted by the app. When running as a test host the app skips launch setup (hotkeys, clipboard polling, menu bar item, music module).
- Bundle id: `com.macdynamicisland.app`. Product name: `MacDynamicIsland`.

## Layout

```text
MacDynamicIsland/              App target. Folders are synced with Xcode: add or move files on disk, no project edits
  App/                         @main entry, AppDelegate, AppIntegration (starts the monitors and the agent hook server), StatusBarController
  Island/                      The island itself: IslandController (one IslandWindow per display), NotchHomeView (root view)
                               and its regions, NotchMetrics, AppState, IslandTab + TabStore (which tabs show),
                               interaction/visibility enums, background, swipes
  Features/
    Music/                     MusicStore, NowPlayingClient (MediaRemote via adapter), LyricsClient, music views
    Agents/                    Hook events, socket server, session store, hook installer, terminal focusing, agent views
    Clipboard/                 ClipboardMonitor (pasteboard polling), ClipboardStore, clipboard views
    Shelf/                     Shelf items, view model, persistence, thumbnails, Quick Look, drag detection
    Plugins/                   PluginStore, PluginClient (one process per plugin), PluginMessage/PluginEvent (the protocol),
                               PluginCatalogClient (plugins repo), plugin views
  Settings/                    Settings window and one view per tab
  System/                      macOS integration: hotkeys, screens, menu bar space, full-screen video, login item, AppleScript
  Shared/                      Extensions, reusable components, utilities (settings keys, L("key"), logging, build config)
  Resources/                   Assets, en.lproj/Localizable.strings, Info.plist, entitlements
MacDynamicIslandTests/         Unit tests (hosted by the app)
Helpers/
  ClaudeHookBridge/            island-claude-hook: the command every agent's hooks run
  MediaRemoteAdapter/          Library loaded into perl by the now-playing helper process (exports mediaremote_adapter_stream)
Plugins/
  timer/                       Sample plugin and the template for new ones; Launch.command builds and installs it
```

## Conventions

- One main type per file, named after the type. A small private subview used by only that type may stay in its file.
- Type suffixes say what a type is for:
  - `Store`: state the UI observes (`ObservableObject`), e.g. `MusicStore`, `ClipboardStore`, `AgentSessionStore`
  - `Service`: does work without holding UI state, e.g. `ThumbnailService`, `ShelfPersistenceService`
  - `Client`: talks to another process, a private API or the network, e.g. `NowPlayingClient`, `LyricsClient`, `AppleScriptClient`
  - `Monitor`: watches system events and reports them, e.g. `ClipboardMonitor`, `HotKeyMonitor`, `DragMonitor`
  - `Controller`: AppKit window and menu controllers only, e.g. `IslandController`, `StatusBarController`
- The product word is "island" (not overlay), and clipboard history is "clipboard" (not hub or vault).

## How it starts

`MacDynamicIslandApp` (@main) has an empty Settings scene; `AppDelegate.applicationDidFinishLaunching` creates `IslandController.shared` (borderless `IslandPanel` hosting `NotchHomeView`, owns `AppState` and `NowPlayingClient` -> `MusicStore`), `AppIntegration.start()` (ClipboardMonitor, HotKeyMonitor, AgentHookServer) and `StatusBarController`.

## Things that are easy to break

- Since macOS 15.4 mediaremoted only answers Apple-signed processes, so now-playing is read by running `/usr/bin/perl` with `libMediaRemoteAdapter.dylib` and parsing JSON lines. Playback commands go direct.
- Island animation is driven entirely by SwiftUI springs; the panel (`IslandWindow`) is only a viewfinder that grows before expanding and shrinks after the spring settles. Don't add AppKit animation or let SwiftUI content constrain the window (AutoLayout <-> setFrame recursion).
- `@Published` fires at willSet; panel sizing therefore reacts in didSet or on the next runloop turn.
- The island is always dark: `IslandPanel`, its hosting view and the SwiftUI root are pinned to `darkAqua` / `.dark`, so a system light/dark switch never re-resolves its colors. Settings and menus follow the system.
- Glass theme: `NSGlassEffectView` follows its window's active state and has no public switch for it. The island opens on hover or swipe without becoming key, so `IslandPanel` overrides the private `_hasActiveAppearance` / `_hasActiveAppearanceIgnoringKeyFocus` to keep the active look. Without them the glass opens opaque until a click makes the panel key. If the first open turns opaque again on a new macOS, check these first.
- The clear glass has no dimming of its own and blows out over light windows; `IslandBackground` lays a black dimming layer and soft top/side fades over it. Views inside the island should not add their own black over the glass.
- Agent hooks: connecting adds one command hook per event to the agent's config (Claude Code `~/.claude/settings.json`, Codex `~/.codex/hooks.json`, ZCode `~/.zcode/cli/config.json`), backed up to `<file>.mac-island-backup`. The helper talks to the app over a per-user Unix socket, prints nothing and always exits 0. Claude Code's `PermissionRequest` hook runs in the foreground (`claude wait`) so the island can answer questions.
- Tabs: `IslandTab` is a string id (built-in ones, or `plugin.<id>`); `TabStore` keeps up to 6 enabled, saved under `enabledTabs`. Code that jumps to a tab (drag to Files, ⌥⌘V, agent prompts) checks `TabStore.isEnabled` first. Plugin tabs are 270 pt tall, the tallest built-in tab, so they never grow the SwiftUI canvas.
- Plugins: a folder in `~/Library/Application Support/MacDynamicIsland/Plugins/<id>` with `plugin.json` and a program; the protocol is documented in the plugins repo's README (github.com/nyaaorick/island4mac-plugins). The app runs it (`PluginProcess`, posix_spawn) in its own process group while its tab is enabled, reads JSON lines from stdout (`PluginMessage`) and writes taps to stdin (`PluginEvent`) on a background queue, dropping events once 64 KB wait. Stopping closes stdin, sends SIGTERM to the group and SIGKILL 2 s later; quitting does the same within 0.5 s; a crash leaves `PluginData/.running.json`, and the next launch kills what's still running the plugin's program. 6 exits in 60 s and it is marked stopped (reason from its stderr) with a Restart button. Each plugin gets `ISLAND_DATA_DIR` (`PluginData/<id>`, kept across updates). Bump `PluginManifest.supportedProtocol` for an incompatible protocol change. Beside the notch: agents, then plugin popups, then music, then plugin compact content.
- Plugins never style anything: no colors, fonts, images or layout in the protocol. New plugin UI uses the island's existing look (rows, capsule buttons, the agent cards' text field).
- Permissions: Accessibility (hotkeys, full-screen detection on the built-in display), Automation/Apple Events (Music lyrics, paste via System Events, terminal tab focus).
- Shortcuts: ⇧⌘Space toggle, ⌥⌘Space show/hide, ⌥⌘V clipboard tab.
