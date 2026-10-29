# Architecture

## Layout

```text
island4mac/                 App target. Folders are synced with Xcode: add or move files on disk, no project edits
  App/                      @main entry (Island4macApp), AppDelegate, AppIntegration (starts hotkeys, plugins, the
                            update check, the catalog refresh), StatusBarController (the menu bar item)
  Island/                   The island: IslandController (one IslandWindow per display), IslandWindow (the panel and
                            its frame), NotchHomeView (root view) with CompactIslandRegion and ExpandedIslandRegion,
                            NotchMetrics and NotchShape, AppState, IslandTab + TabStore, IslandBackground (themes),
                            drops (IslandDrop, IslandDropTarget, IslandDropZone), SwipeMonitor, LiveActivity
  Music/                    NowPlayingStore (the one track the island shows, from plugins' `media`) and the player
                            views: expanded, compact, beside the notch, the spectrum
  Plugins/
    Protocol/               The wire format as the app reads it: PluginMessage, PluginEvent, PluginManifest,
                            PluginPreference, PluginCard, PluginRowAction, PluginCountdown, PluginTimeline
    Runtime/                Running plugins: PluginStore (what each shows, statuses, schedules), PluginClient (one
                            process, its lines), PluginProcess (posix_spawn), PluginSchedule, PluginFolderMonitor,
                            PluginPreferencesStore, AdminAccessStore (sudo for plugins), ThumbnailService
    Catalog/                The hub: PluginCatalogEntry (index.json), PluginCatalogClient (fetch, verify, unpack,
                            remove), PluginCatalogStore (cache, updates, installs under way)
    Views/                  How plugin content is drawn: PluginTabView, PluginContentView, cards, rows, buttons,
                            symbols and states, the compact views, PluginSettingsButton
  Settings/                 The Settings window (a sidebar of panes) and one view per pane
  System/                   macOS: HotKeyMonitor, ScreenService, MenuBarSpace, FullScreenVideo, KeychainService,
                            DragMonitor, UpdateClient
  Shared/                   Components (IslandSurface, MarqueeText), extensions, utilities (SettingsDefaults, Version,
                            BuildConfig, Localization, Log)
  Resources/                Assets, en.lproj/Localizable.strings, Info.plist, island4mac.entitlements
SharedCore/                 Compiled into the app and into every bundled plugin: PluginImage and PluginMedia (protocol
                            types a plugin makes), AppleScriptClient
BundledPlugins/<id>/        The plugins that ship in the app (agents, clipboard, files, music), on IslandKit:
  Sources/                  the thin IslandPlugin
  Core/                     its logic, compiled into the plugin and into the app so the app's tests cover it
  plugin.json               written by `<id> --describe`, never by hand (a test checks)
island4macTests/            Unit tests, hosted by the app
Helpers/ClaudeHookBridge/   island-claude-hook: the command every agent's hooks run (Darwin only, about 27 ms)
Helpers/MediaRemoteAdapter/ Library loaded into perl by the Music plugin's now-playing process
spec/                       Documents and skills
```

## Conventions

- One main type per file, named after the type. A small private subview used by only that type may stay in its file.
- Type suffixes: `Store` holds state the UI observes (`ObservableObject`); `Service` does work without UI state; `Client` talks to another process, a private API or the network; `Monitor` watches system events; `Controller` is an AppKit window or menu controller.
- The product word is "island" (not overlay); clipboard history is "clipboard".
- Logging: `Logger(subsystem: Log.subsystem, category: "<Type>")`; a bundled plugin, which has no `Log`, uses its bundle id. No `print`.
- Settings: a key in `SettingsDefaults` has a reader somewhere. Views read through `ToggleSettingsRow` and `SliderSettingsRow`.

## How it starts

`Island4macApp` (@main) has an empty Settings scene. `AppDelegate.applicationDidFinishLaunching` makes `IslandController.shared` (an `IslandPanel` per display hosting `NotchHomeView`, owning `AppState`, with `NowPlayingStore` fed by plugins' `media`), `StatusBarController`, and `AppIntegration.start()`: `HotKeyMonitor`, `PluginStore.start()` (which runs the bundled plugins and the ones whose tabs are on), then the update check (Release builds) and the catalog refresh.

## The island

- **Animation** is driven entirely by SwiftUI springs (`IslandAnimation`, taken from boring.notch). `IslandWindow` is a viewfinder: the panel grows at once before the island expands and shrinks after the spring settles (0.6 s). No AppKit animation, and SwiftUI content never constrains the window (AutoLayout and `setFrame` would recurse).
- `@Published` fires at willSet; panel sizing reacts in didSet or on the next runloop turn (`islandSizeDidChange`).
- **Always dark**: `IslandPanel`, its hosting view and the SwiftUI root are pinned to `darkAqua` / `.dark`, so a system appearance switch never re-resolves the island's colors. Settings and menus follow the system.
- **Glass** (macOS 26): `NSGlassEffectView` follows its window's active state and has no public switch for it. The island opens on hover without becoming key, so `IslandPanel` overrides the private `_hasActiveAppearance` and `_hasActiveAppearanceIgnoringKeyFocus`. If the glass opens opaque on a new macOS, check these first. The glass is the `.clear` style under a black dimming layer and soft fades (`IslandBackground`). Views inside the island draw no backgrounds of their own: `.islandTile()` is a pane of clear glass a step deeper, `.islandInset()` deeper again; hover and selection go deeper, never lighter (`IslandSurface`).
- **Beside the notch** (`LiveActivity.pick`): a high-priority plugin, then a plugin popup, then music while it plays (or paused while the pointer rests on the notch), then a plugin's compact content. The wings take only the room menus and status icons leave (`MenuBarSpace`).
- **Tabs**: `IslandTab` is a string id (built-in, or `plugin.<id>`); `TabStore` keeps up to 6 enabled under `enabledTabs`. Code that jumps to a tab checks `TabStore.isEnabled` first. Plugin tabs are 270 pt tall, the tallest built-in tab, so they never grow the canvas.
- **Drops**: `DragMonitor` notices a drag near the notch and `AppState` opens the island on the tab that takes drops (`IslandDropTarget`); `IslandDropZone` draws where to drop; `IslandDrop` reads files as paths, text as a file in the plugin's `Drops/` folder, links as URLs.

## Plugins at run time

- A plugin is a folder with `plugin.json` and a program, in `~/Library/Application Support/island4mac/Plugins/<id>` (`island4mac Dev` for the dev app), or bundled in the app at `Contents/Resources/Plugins/<id>` with its program in `Contents/Helpers` (code can't sit among resources in a signed app). `PluginStore.scan` finds both, bundled first; an installed plugin with a bundled id is refused.
- `PluginProcess` spawns it (posix_spawn, its own process group) with `ISLAND_PROTOCOL`, `ISLAND_PLUGIN_ID`, `ISLAND_DATA_DIR` (`PluginData/<id>`, kept across updates), `ISLAND_APP_VERSION`. `PluginClient` reads JSON lines from its stdout (dropping a line over 64 KB) and writes events to its stdin, dropping events once 64 KB wait. Stopping closes stdin, sends SIGTERM to the group and SIGKILL 2 s later; quitting the app does the same within 0.5 s; a crash leaves `PluginData/.running.json` and the next launch kills what is still running the plugin's program. 6 exits in 60 s marks it stopped, with its last stderr lines as the reason.
- `PluginFolderMonitor` restarts only the plugin whose files changed (an install, an update, `island-plugin dev`); Settings > Plugins > Reload restarts all.
- Preferences (protocol 2) are kept by `PluginPreferencesStore` (UserDefaults `pluginPreferences.<id>`, secure ones in the Keychain) and sent as a `preferences` event before `visible`; a required one left empty keeps the plugin from starting (`.needsSetup`).
- On-demand plugins (protocol 3) are started when their tab shows, on a tap, at their timeline's `wake`, or when a preference changes, and stopped when they say `done` (`.sleeping`). The island applies timeline entries itself (`PluginSchedule`), catching up after sleep and clock changes, and stops one left running silent with its tab hidden after 30 s. `PluginClient.shownLines` keeps the last line of each kind the plugin wrote; `finish` writes them to `PluginData/<id>/.shown.json`, and the next launch shows them again (`restoreShown`) instead of running the plugin once. A new build of the plugin deletes that file, so it shows itself again.
- Administrator access (protocol 8): `AdminAccessStore` keeps the one password (Keychain) and which plugins may use it; a `sudo` message from an allowed plugin runs `sudo -S -k -p '' -- <command>` off the main thread with the password on stdin and answers with a `sudo` event. A refusal never reaches sudo.
- `NowPlayingStore` picks one track from every plugin's `media` (a playing one first, then the one that changed last); the island runs the progress itself (`PluginMedia.position(at:)`) and loads the artwork. The Music tab is the island's player for that track; another plugin's tab that sends `media` shows the player for its own (`NowPlayingStore(only:)`).

## Things that are easy to break

- Since macOS 15.4 mediaremoted only answers Apple-signed processes, so now playing is read by running `/usr/bin/perl` with `libMediaRemoteAdapter.dylib` and parsing JSON lines. The Music plugin finds the adapter at `Contents/Helpers/../Frameworks`.
- Agent hooks: connecting adds one command hook per event to the agent's config (Claude Code `~/.claude/settings.json`, Codex `~/.codex/hooks.json`, ZCode `~/.zcode/cli/config.json`), backed up to `<file>.island4mac-backup`. The helper talks to the Agents plugin over `Application Support/<bundle id>/hook.sock`, prints nothing and always exits 0. Claude Code's `PermissionRequest` hook runs in the foreground so the island can answer.
- Clipboard pastes by closing the island (`close`), which hands the keyboard back to the app you were using, then sending ⌘V through System Events.
- Permissions: Accessibility (hotkeys, full-screen detection on the built-in display), Automation (lyrics from Music, paste, terminal focus). Neither is asked for at launch; Settings > General has the button.
