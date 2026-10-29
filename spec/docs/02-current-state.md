# Current state

As of 2026-10-29, after the restructuring on branch `island-plugins`. Release 1.1.0 is the one on GitHub; what is described here ships in the next release (see `08-changelog.md`).

## Requirements

- macOS 26.0 or later; Xcode 26 to build. Deployment target 26.0.
- The plugins repo cloned beside this one at `../island4mac-plugins`: the bundled plugins depend on IslandKit as a local package.

## Features

| Area | State |
| --- | --- |
| Island | One `IslandWindow` per display (the chosen one, or every display with "all displays" on; follows the mouse when asked). Opens on hover, tap, two-finger swipe, ⇧⌘Space. Hides for a full-screen video of the playing app. Themes: solid (black, dark gray, deep blue, deep red) and Liquid Glass |
| Beside the notch | In order: a high-priority plugin (Agents), a plugin popup, music while it plays (or paused, while the pointer rests on the notch), a plugin's compact content |
| Tabs | Up to 6, three either side of the camera; built-in Music, Clipboard, Files, Agents plus one per installed plugin; order and selection under Settings > Tabs |
| Music | `NowPlayingStore` picks one track from every plugin that sends `media`; the Music plugin reads MediaRemote through the perl adapter and fetches lyrics from LrcLib or NetEase |
| Agents | Claude Code, Codex and ZCode hooks through `island-claude-hook` over a Unix socket; sessions as rows with states, questions and permission prompts answered in the island |
| Clipboard | History in the plugin's data folder, pictures as files, paste by ⌘V through System Events; ⌥⌘V opens it |
| Files | A shelf fed by drops on the island |
| Plugins | Protocol 8 (`PluginManifest.supportedProtocol`). Persistent and on-demand lifecycles, timelines the island runs itself, preferences drawn in Settings, pictures, row actions, cards, drops, media, states, sections, toggles, progress, confirmations, administrator access |
| Hub | Settings > Plugins: installed plugins with their version, status, switch, update button and menu (Finder, data folder, homepage, uninstall); Update All; the catalog's not-yet-installed plugins with description, author, size and a search field; Install from File (a zip or folder); install phases shown; the catalog cached on disk and refreshed at launch and every 6 hours; a badge on the Plugins sidebar item with the number of updates; a custom catalog address under Advanced |
| Administrator access | One password in the Keychain, a shield per plugin that declares `needs: ["admin"]`; plugins run commands as root through the island (`sudo` messages), never seeing the password |
| On-demand plugins | What one last showed is kept in its data folder (`.shown.json`) and shown again at the next launch without running it |
| Updates | A Release build checks GitHub at launch and installs a newer DMG over itself (`UpdateClient`), checked against its own designated requirement |
| Settings | General, Appearance, Tabs, Plugins, Media, Shortcuts (fixed), Advanced, About |

## Removed in the restructuring

Settings that had no effect (menu bar icon toggle, window shadow, lighting effect, gradient background, colored spectrum, control slot limit, slider color, settings icon in the notch, idle face toggle, remember last tab), the carry-over of pre-plugin settings and data (clipboard history in UserDefaults, the old shelf file, agent and music settings), the memory logger, the unused localization keys (about 110 of 210), the debug menu, upstream file headers and emoji comment markers. The support folder moved from `Application Support/MacDynamicIsland` to `Application Support/island4mac` (the app moves it once, `BuildConfig.supportFolder`).

## Plugins outside the catalog

Clash Mihomac (`~/Developer/island4mac-workspace/clash-mihomac`, Go) runs as a plugin with `mihomac island`: the daemon, dashboard and MCP server in-process, its data in `ISLAND_DATA_DIR`; `make plugin-install` there installs it. Storage (System Data Boomer plus the app-residue cleaner) and the Wi-Fi login helper are the next two, as IslandKit plugins that use administrator access.

## Known gaps

- Lyrics from QQ Music: `LyricsClient` only reaches LrcLib and NetEase.
- The AppIcon asset set is empty.
- Keyboard shortcuts are fixed.
- Releases are not notarized (no paid developer account), so the first launch needs Open Anyway.
