# CLAUDE.md

macOS menu bar app (Swift, SwiftUI + AppKit) that turns the MacBook notch into a "Dynamic Island": now playing with lyrics, coding-agent progress (Claude Code, Codex, ZCode), clipboard history and a drag-and-drop file shelf. Based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Rules for this repo

- English only: code, comments, log messages, UI strings and test fixtures. The only localization is `MacDynamicIsland/Resources/en.lproj/Localizable.strings` (read through `L("key")` in `Shared/Utilities/Localization.swift`).
- Swift only: no C, Objective-C or shell files, including the two helpers (`Helpers/ClaudeHookBridge/main.swift`, `Helpers/MediaRemoteAdapter/MediaRemoteAdapter.swift`). The hook helper runs on every agent hook event, so keep it to `import Darwin` and check its startup time (about 27 ms per run, same as the old C version) after changing it.
- Docs are limited to this file, `README.md`, `CHANGELOG.md` (what each release changed), `roadmap.md`, `backup.md` and `BundledPlugins/README.md` (bundled plugins, IslandKit and the protocol). Do not add a `docs/` folder. Keep the README short.
- Plugin docs live in two places: IslandKit and the protocol in the plugins repo's README (github.com/nyaaorick/island4mac-plugins), and again in `BundledPlugins/README.md`, after what is different about bundled plugins. The two copies say the same (only "this repo" and relative links are reworded); a change to IslandKit or the protocol updates both.
- The app is not sandboxed (MediaRemote and AppleScript need that). Distribution is a DMG on GitHub Releases, signed with a self-signed certificate and not notarized (no paid Apple developer account); the app updates itself from there. No third-party dependencies for that: see Releasing.

## Build and test

<!-- AUTO-GENERATED from MacDynamicIsland.xcodeproj -->

| Command | Description |
|---|---|
| `open MacDynamicIsland.xcodeproj` | Open in Xcode (scheme `MacDynamicIsland`, pick a team under Signing & Capabilities) |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' build` | Build |
| `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -destination 'platform=macOS' test` | Run unit tests |

<!-- END AUTO-GENERATED -->

- `Launch.command` (double-click in Finder) builds the dev app into `build/` and opens it, after quitting a dev build already running (never the installed release). It is a Swift script (`#!/usr/bin/env swift`), not shell.
- `Release.command` builds the release DMG into `build/Release/`; `./Release.command --publish` also publishes it (Releasing). A Swift script too.
- Deployment target is macOS 26.0.
- Tests (`MacDynamicIslandTests`) are hosted by the app. When running as a test host the app skips launch setup (hotkeys, clipboard polling, menu bar item, music module).
- Bundle id: `com.macdynamicisland.app` for Release builds, `com.macdynamicisland.app.dev` for Debug builds (the dev app, "Mac Dynamic Island Dev": Dev builds). Product name: `MacDynamicIsland`.

## Layout

```text
MacDynamicIsland/              App target. Folders are synced with Xcode: add or move files on disk, no project edits
  App/                         @main entry, AppDelegate, AppIntegration (starts the monitors and the plugins), StatusBarController
  Island/                      The island itself: IslandController (one IslandWindow per display), NotchHomeView (root view)
                               and its regions, NotchMetrics, AppState, IslandTab + TabStore (which tabs show),
                               interaction/visibility enums, background, swipes
  Features/
    Music/                     NowPlayingStore (what the island shows as playing, from plugins' `media`), the player views
    Plugins/                   PluginStore, PluginClient (one process per plugin), PluginMessage/PluginEvent (the protocol),
                               PluginSchedule (timelines), PluginImage, PluginPreferencesStore, PluginFolderMonitor,
                               PluginCatalogClient (plugins repo), plugin views
  Settings/                    Settings window and one view per tab
  System/                      macOS integration: hotkeys, screens, menu bar space, full-screen video, login item, Keychain,
                               drag detection (DragMonitor), app updates (UpdateClient)
  Shared/                      Extensions, reusable components, utilities (settings keys, L("key"), logging, build config)
  Resources/                   Assets, en.lproj/Localizable.strings, Info.plist, entitlements
SharedCore/                    AppleScriptClient, and the protocol types a plugin makes: PluginImage, PluginMedia.
                               Compiled into the app and into every bundled plugin
BundledPlugins/                The plugins that ship in the app, on IslandKit: agents, clipboard, files, music (targets
                               AgentsPlugin, ClipboardPlugin, FilesPlugin, MusicPlugin; products named by id). Each is
                               Sources/ (the thin IslandPlugin), Core/ (its logic) and plugin.json written with
                               `<id> --describe` (a test checks they all match). README.md: how to build, change and add one
  agents/Core/                 Hook events and socket, installers, session store, transcripts, terminal focus, sounds
  clipboard/Core/              ClipboardStore (history in its data folder), ClipboardMonitor (pasteboard polling),
                               FrontmostAppMonitor (the app a paste goes into)
  files/Core/                  ShelfStore and its persistence
  music/Core/                  MusicStore (what plays, as PluginMedia, with lyrics and artwork), NowPlayingClient
                               (MediaRemote via the adapter), LyricsClient
                               Each Core/ is compiled into its plugin and into the app (one synced folder, two targets),
                               so its tests run in the app's; no SwiftUI, Settings or island types in them
MacDynamicIslandTests/         Unit tests (hosted by the app)
Helpers/
  ClaudeHookBridge/            island-claude-hook: the command every agent's hooks run
  MediaRemoteAdapter/          Library loaded into perl by the now-playing helper process (exports mediaremote_adapter_stream)
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

`MacDynamicIslandApp` (@main) has an empty Settings scene; `AppDelegate.applicationDidFinishLaunching` creates `IslandController.shared` (borderless `IslandPanel` hosting `NotchHomeView`, owns `AppState`; starts `NowPlayingStore`, fed by plugins' `media`), `AppIntegration.start()` (HotKeyMonitor, PluginStore, which runs the bundled Music, Clipboard, Files and Agents plugins, and in Release builds the update check) and `StatusBarController`.

## Dev builds

Day to day you run the installed release: the DMG from GitHub in /Applications, updated by the app itself like everyone else's copy, so what you use is what users get. Development happens in the dev app, which never touches it:

- Every Debug build (Xcode, `Launch.command`, the unit tests' host) is the dev app: bundle id `com.macdynamicisland.app.dev`, named "Mac Dynamic Island Dev". Its settings are its own defaults domain, its plugins and their data are in `~/Library/Application Support/MacDynamicIsland Dev` (`BuildConfig.supportFolderName`), its agents helper and socket in `Application Support/com.macdynamicisland.app.dev`, its Keychain items under its bundle id, and macOS asks for its permissions separately ("Mac Dynamic Island Dev" in Privacy & Security). It never checks for updates.
- The installed release keeps `com.macdynamicisland.app`, `Application Support/MacDynamicIsland` and `Application Support/com.macdynamicisland.app`: your real settings, clipboard history, shelf and plugins.
- One notch: a dev build quits the installed release when it starts and reopens it when it quits (`AppIntegration.quitInstalledRelease` / `reopenInstalledRelease`, Debug only; the release's path is kept in the dev app's defaults, so a dev build killed and rebuilt still brings it back). Stopping a dev build in Xcode kills it, so that one doesn't: the next dev build you quit normally does, or open the release yourself.
- Agent hooks follow whichever copy runs: on start, each points the connected agents' hooks at its own helper and socket (`refreshIfInstalled`), so a dev build gets the agents' events while it runs and the release takes them back when it returns. The switch rewrites the hooks in the agents' config files, keys sorted.
- `island-plugin dev` (plugins repo) installs into the release's plugins folder; to try a plugin in the dev app, copy it into `MacDynamicIsland Dev/Plugins`.
- Keep it this way: anything new the app stores goes under a name the identity decides (the bundle id, `BuildConfig.supportFolderName`), never a fixed one both copies would share.

## Releasing

A release is `island4mac.dmg` on the GitHub release `v<version>`, made by `Release.command`. There is no paid Apple developer account, so the app is signed with a self-signed certificate and not notarized. Each time it launches, a Release build asks GitHub for the latest release and offers to install it if it is newer (`AppIntegration.checkForUpdate`, `UpdateClient`).

Every release, in this order:

1. Raise `MARKETING_VERSION` of the `MacDynamicIsland` target (Debug and Release). Versions compare number by number (`1.10` > `1.9`); only ever go up.
2. Add `## <version>` at the top of `CHANGELOG.md`: what changed, for users. It becomes the release notes, and `--publish` refuses a version without it.
3. Update the other docs the release touches: `README.md` (features, install, requirements), this file (code, rules, this process), `roadmap.md` (drop what's done). Commit and push.
4. `./Release.command` builds and checks `build/Release/island4mac.dmg`. Try it as the release it will be: quit the installed copy, open the DMG and run the app from it (same identity, so your real settings and data), then quit it. Then `./Release.command --publish` publishes it as `v<version>` (it needs a clean, pushed commit and `gh` logged in).
5. Open your installed copy: it offers the update, installs it and comes back as the new version, its Accessibility and Automation permissions intact. You go through exactly what users do. The first real update also confirms macOS's App Management protection leaves it alone (Apple describes it for notarized apps; if an update fails with "prevented from modifying apps", that is the cause).

How it fits together:

- The certificate "island4mac Release" (self-signed, valid until 2046, SHA-1 `0549e796d95b726aaf3976ba02629b29b8367590`) is in the maintainer's login keychain, with a backup in `~/.island4mac-release-keys/` (the .p12 and its password; keep a copy in a password manager). On another Mac, import it: `security import island4mac-release.p12 -k ~/Library/Keychains/login.keychain-db -P <password> -T /usr/bin/codesign`. Never make a new one, and never change the bundle id: the designated requirement is `identifier "com.macdynamicisland.app" and certificate leaf = H"<that SHA-1>"`, installed copies take only updates that satisfy it, and macOS ties the app's permissions to it. `Release.command` refuses a build signed any other way.
- `UpdateClient` downloads the release's first `.dmg` asset, mounts it, copies the app out, checks its signature against the running app's designated requirement and its version against the tag, swaps it in for the running app and relaunches it (a short `sh` wait, so the new copy starts only after this one quits). Anything that fails leaves the installed app as it was and offers the release page instead.
- Only the first install meets Gatekeeper: the user opens the app once through System Settings > Privacy & Security > Open Anyway (README, Install). Updates are downloaded by the app itself, so they carry no quarantine and open without asking.
- Debug builds (the dev app) never check. A Release build signed some other way (a team, ad hoc) is offered updates but refuses to install them.
- The Hardened Runtime stays on without library-validation exceptions: nothing third-party loads into the app. A framework added to it would need `com.apple.security.cs.disable-library-validation`, because a self-signed app has no Team ID.

## Things that are easy to break

- Since macOS 15.4 mediaremoted only answers Apple-signed processes, so now-playing is read by running `/usr/bin/perl` with `libMediaRemoteAdapter.dylib` and parsing JSON lines. Playback commands go direct. Both happen in the Music plugin, which finds the adapter at `Contents/Helpers/../Frameworks`.
- Island animation is driven entirely by SwiftUI springs; the panel (`IslandWindow`) is only a viewfinder that grows before expanding and shrinks after the spring settles. Don't add AppKit animation or let SwiftUI content constrain the window (AutoLayout <-> setFrame recursion).
- `@Published` fires at willSet; panel sizing therefore reacts in didSet or on the next runloop turn.
- The island is always dark: `IslandPanel`, its hosting view and the SwiftUI root are pinned to `darkAqua` / `.dark`, so a system light/dark switch never re-resolves its colors. Settings and menus follow the system.
- Glass theme: `NSGlassEffectView` follows its window's active state and has no public switch for it. The island opens on hover or swipe without becoming key, so `IslandPanel` overrides the private `_hasActiveAppearance` / `_hasActiveAppearanceIgnoringKeyFocus` to keep the active look. Without them the glass opens opaque until a click makes the panel key. If the first open turns opaque again on a new macOS, check these first.
- The island's glass is `NSGlassEffectView` in the `.clear` style under a black dimming layer and soft top/side fades (`IslandBackground`); the clear glass has no dimming of its own and blows out over light windows without it. Views inside the island draw no backgrounds of their own: a module, card or row is `.islandTile()` (a pane of the system's clear Liquid Glass, `.glassEffect`, a step deeper than the glass it lies on) and a field or preview inside it is `.islandInset()` (deeper again). Hover and selection go deeper, never lighter (`Shared/Components/IslandSurface.swift`), so every tab reads as the same stack of glass. Leave room in scroll views for the tile shadow.
- Agent hooks: connecting adds one command hook per event to the agent's config (Claude Code `~/.claude/settings.json`, Codex `~/.codex/hooks.json`, ZCode `~/.zcode/cli/config.json`), backed up to `<file>.mac-island-backup`. The helper talks to the Agents plugin over a per-user Unix socket (`Application Support/<bundle id>/hook.sock`: the release keeps the path the app always used, the dev app has its own), prints nothing and always exits 0; with the plugin off or restarting, it exits at once and the agent asks in its terminal. Claude Code's `PermissionRequest` hook runs in the foreground (`claude wait`) so the island can answer questions.
- Tabs: `IslandTab` is a string id (built-in ones, or `plugin.<id>`); `TabStore` keeps up to 6 enabled, saved under `enabledTabs`. Code that jumps to a tab (drag to Files, ⌥⌘V, agent prompts) checks `TabStore.isEnabled` first. Plugin tabs are 270 pt tall, the tallest built-in tab, so they never grow the SwiftUI canvas.
- Plugins: a folder in `~/Library/Application Support/MacDynamicIsland/Plugins/<id>` (`MacDynamicIsland Dev` for the dev app) with `plugin.json` and a program; the protocol is documented in the plugins repo's README (github.com/nyaaorick/island4mac-plugins), which also holds the sample plugins (the timer among them). New plugins use IslandKit, the Swift SDK there (`island-plugin new`). The app runs it (`PluginProcess`, posix_spawn) in its own process group while its tab is enabled, reads JSON lines from stdout (`PluginMessage`) and writes taps to stdin (`PluginEvent`) on a background queue, dropping events once 64 KB wait. Stopping closes stdin, sends SIGTERM to the group and SIGKILL 2 s later; quitting does the same within 0.5 s; a crash leaves `PluginData/.running.json`, and the next launch kills what's still running the plugin's program. 6 exits in 60 s and it is marked stopped (reason from its stderr) with a Restart button. Each plugin gets `ISLAND_DATA_DIR` (`PluginData/<id>`, kept across updates). Bump `PluginManifest.supportedProtocol` when the protocol gains something (now 7); a plugin declares the oldest it needs and older apps refuse it. `PluginFolderMonitor` restarts only the plugin whose files changed (installs, updates, `island-plugin dev`); Settings > Plugins > Reload restarts all. Beside the notch (`LiveActivity.pick`): high-priority plugins (Agents is one), then plugin popups, then music, then plugin compact content.
- Plugin preferences (protocol 2): declared in plugin.json, drawn by `PluginPreferencesView` under Settings > Plugins, kept by `PluginPreferencesStore` (UserDefaults `pluginPreferences.<id>`, secure ones in the Keychain), sent as a `preferences` event before `visible`. A required one left empty keeps the plugin from starting (`.needsSetup`).
- On-demand plugins (protocol 3, `"lifecycle":"onDemand"`): started when their tab shows, on a tap, at a `wake` time from their `timeline` message, or when a preference changes; they say `done` and are stopped, and what they showed stays (`.sleeping`). The island applies timeline entries itself (`PluginSchedule`), catching up after sleep and clock changes, and stops one left running and silent with its tab hidden after 30 s. IslandKit's plugin.json for each kind of preference is copied into `PluginTests.testIslandKitsPluginJSONLoads`; keep it in step with the plugins repo's fixture.
- Protocol 4: pictures on rows and compact content (`PluginImage`: a file path, an app icon, an https URL; the island sizes and caches them), row actions (`PluginRowAction`), and plugin.json `"background": true` (runs while turned on, tab or not) and `"priority": "high"` (ahead of popups and music beside the notch). Every plugin has an Enabled switch in Settings > Plugins.
- Protocol 5: cards (`PluginCard`), a row turned on its side with a large `preview` (text or a picture) and an optional `file` that drags out; they sit in one sideways-scrolling row above the rows (`PluginContentView`, `PluginCardView`). Buttons alone in a tab show larger, in its middle. Plugin.json `"accepts":["files"]` makes a tab take drops: the island opens on it when a drag nears the notch, draws the drop highlight (`IslandDropZone`), reads the drop (`IslandDrop`: files as paths, text saved to `PluginData/<id>/Drops`, links as URLs) and sends `{"type":"drop","paths":[…],"urls":[…]}` (`IslandDropTarget`). A plugin's `close` also closes an island open on its tab for you (after a paste), not only one it held.
- Protocol 6: a `state` on rows, cards and compact content (`PluginItemState`: working, attention, done, failed) and a `detail` on rows (short text at the right edge). The island draws the state (`PluginSymbolView`: a turning arc for working, a pulsing symbol for attention, the colors in `PluginItemState+Look.swift`; a row's first subtitle line is its status line, in the state's color). A state the app doesn't know reads as none. The Agents plugin's sessions are the model: `AgentLook` in `AgentsPlugin.swift` maps a session to its state, symbol, status line and detail.
- Protocol 7: rows gain `kind` (`section`: a caption over the rows after it, `PluginSectionView`, never tapped), `progress` (a ring around the symbol, as compact content has) and `toggle` (a switch at the row's end; it and the row send the row's action, the plugin flips the value), and row and card actions gain `confirm` (asked in the tab first, like a button's; `PluginConfirmation` in `PluginContentView`). IslandKit leaves an action with `confirm` out on apps before 7 rather than let it run unasked.
- Media (protocol 5): `{"type":"media",…}` (`PluginMedia`: title, artist, album, artwork as a PluginImage, `app` bundle id, playing, elapsed as of `at`, duration, rate) and `{"type":"lyrics","lines":[{"time":…,"text":…}]}`; the island answers its player's taps with `control` ("playPause", "next", "previous") and `seek`. `NowPlayingStore` picks one track from every source (a playing one first, then the one that changed last) and is all the island reads: the player views, music beside the notch, the paused-music fold, `FullScreenVideo` (by `app`). The island runs the progress itself (`PluginMedia.position(at:)`) and loads the artwork. The Music plugin's `MusicStore` produces exactly this data (artwork as a file in PluginData/music/Artwork, an app icon or an iTunes URL). The Music tab is the island's player for the track `NowPlayingStore` picked; another plugin's tab that sends `media` shows the player for its own track (`NowPlayingStore(only:)`).
- Clipboard, Files and Music are bundled plugins like Agents: their tabs (`IslandTab.builtInTabsOfPlugins`) keep their place and name, their settings are preferences under Settings > Plugins (carried over once by `AppIntegration.carrySettingsOver`; the Media pane keeps only how the island draws music), and their data is in their data folders (moved once from UserDefaults and Application Support). Clipboard runs in the background and pastes by closing the island (`close`), which hands the keyboard back to the app you were using, then sending ⌘V through System Events. Files takes drops; its empty tab's button opens a file panel from the plugin process.
- Bundled plugins: folders in `Contents/Resources/Plugins/<id>` (one "Embed Bundled Plugin <id>" copy phase each) with their programs in `Contents/Helpers` (code can't sit among resources in a signed app). Updated with the app; can be turned off in Settings > Plugins, not removed. One in `IslandTab.builtInTabsOfPlugins` draws that built-in tab, which keeps its place and name.
- Agents is the bundled Agents plugin, drawn with the protocol only: no native Agents views and no Settings pane. Its settings (sounds, beside the notch, open the island) are its preferences under Settings > Plugins, carried over once from the old Settings keys (`AppIntegration.carrySettingsOver`); connecting agents is in its tab. A question opens the island with `{"type":"open","hold":true}` and `{"type":"close"}` lets go once it's answered (`.heldByPlugin`: no auto-close meanwhile). A tab whose plugin has preferences gets a gear (`PluginSettingsButton`). The AgentsPlugin target needs IslandKit, referenced as a local package at `../island4mac-plugins` until the plugins repo is tagged. `ISLAND_AGENTS_SOCKET` gives the Agents plugin a socket of its own (tests).
- Plugins never style anything: no colors, fonts or layout in the protocol; a picture says only where it comes from. New plugin UI uses the island's existing look (rows, capsule buttons, the agent cards' text field).
- Permissions: Accessibility (hotkeys, full-screen detection on the built-in display), Automation/Apple Events (Music lyrics, paste via System Events, terminal tab focus).
- Shortcuts: ⇧⌘Space toggle, ⌥⌘Space show/hide, ⌥⌘V clipboard tab.
