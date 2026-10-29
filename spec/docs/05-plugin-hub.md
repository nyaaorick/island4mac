# The plugin hub

Settings > Plugins is where plugins are found, installed, updated, set up and removed. `PluginCatalogStore` holds its state, `PluginCatalogClient` does the work, `PluginsSettingsView` draws it.

## Bundled plugins

`agents`, `clipboard`, `files` and `music` ship inside the app as ordinary IslandKit plugins, built with it and updated with it. Their folders are `Contents/Resources/Plugins/<id>` (one "Embed Bundled Plugin <id>" copy phase each) and their programs `Contents/Helpers/<id>`. Users can turn them off, not remove them; the catalog never offers them an update. Each one draws a built-in tab (`IslandTab.builtInTabsOfPlugins`), which keeps its place and name. Their settings are preferences under Settings > Plugins. Changing or adding one: `spec/skills/bundled-plugin/SKILL.md`.

IslandKit comes from the plugins repo as a local package at `../island4mac-plugins`, so the two repos are cloned side by side.

## The catalog

The catalog is an `index.json` at the address under Settings > Advanced (by default the plugins repo's, on GitHub). Each entry:

```json
{"id":"timer","name":"Timer","symbol":"timer","version":"2.0.0","protocol":3,
 "description":"Countdown beside the notch, with presets and pause",
 "archive":"https://github.com/nyaaorick/island4mac-plugins/releases/download/timer-2.0.0/timer.zip",
 "sha256":"…","size":123456,"author":"nyaaorick",
 "homepage":"https://github.com/nyaaorick/island4mac-plugins/tree/main/timer","updated":"2026-10-29"}
```

`id`, `name`, `version`, `protocol` and `archive` (https, or a file on this Mac) are required; the rest is optional, and an index without them still installs. `island-plugin publish` in the plugins repo writes all of them: it releases every built version that has no release yet, computes the archive's SHA-256 and size, and rewrites the index.

The app reads the index when the pane opens, at launch, and when it's older than 6 hours (`PluginCatalogStore.staleAfter`), and keeps the last copy at `Application Support/island4mac/catalog.json`, so the pane shows at once and offline (with an orange note). The Plugins item in the Settings sidebar carries the number of installed plugins the catalog has a newer version of.

## Installing and updating

1. The archive is downloaded (phase "Downloading…").
2. With a `sha256` in the index, the download's SHA-256 must match (phase "Checking…"); otherwise the install stops with "doesn't match the catalog's checksum".
3. It is unpacked with `ditto`, which keeps the program's executable bit. The archive may hold the plugin's files or one folder with them. Its `plugin.json` must load, its `id` must be the index's, and its `version` (if it has one) must be the index's.
4. The folder goes into the plugins folder as `<id>`, replacing the old copy in one step (phase "Installing…"). `PluginFolderMonitor` restarts only that plugin.
5. A new plugin's tab is turned on when fewer than six show.

An update is the same install for an entry whose `version` is newer than the installed one (`Version`, number by number, so 1.10 is newer than 1.9; a downgrade is never offered). "Update to x.y.z" sits on the installed row; "Update All (n)" in the section header runs them one after another.

**Install from File…** takes a plugin's zip or its folder from this Mac, with the same checks but no index: for a plugin you wrote, or one published elsewhere. A folder is copied, not moved.

**Uninstall** moves the plugin's folder and its data folder to the Trash (so a slip can be undone) and forgets its preferences. The installed row's menu also opens the plugin in Finder, its data folder, and its homepage from the index.

## Administrator access

Settings > Plugins has one "Administrator access" section, shown once a plugin that declares `"needs": ["admin"]` is installed: a password field (checked with `sudo /usr/bin/true` before it is saved to the Keychain under `<bundle id>.admin`) and a Forget button. Each plugin that needs it has a shield beside its name; off by default. `AdminAccessStore` keeps both and runs the commands (`PluginMessage.sudo`); `PluginStore.runAsAdministrator` refuses a plugin that didn't declare the need before it ever reaches the store. The protocol side is `04-plugin-protocol.md`, "Administrator access".

## What the island keeps for a plugin

| Where | What | Survives |
| --- | --- | --- |
| `Plugins/<id>/` | The plugin as installed | Until uninstalled; replaced by an update |
| `PluginData/<id>/` | `ISLAND_DATA_DIR`: whatever it keeps; `Drops/` for text dropped on it; `.shown.json`, what an on-demand plugin last showed | Updates; removed with the plugin |
| UserDefaults `pluginPreferences.<id>`, the Keychain for secure ones | Its preferences | Updates; removed with the plugin |
| UserDefaults `disabledPlugins` | Which plugins are turned off | Everything |
| UserDefaults `adminAllowedPlugins`, Keychain `<bundle id>.admin` | Which plugins may run commands as an administrator, and the password | Everything, until Forget |
| `PluginData/.running.json` | The running plugins, to end what a crash left | Until the next launch |
| `catalog.json` | The last catalog read | Until the catalog address changes |

## Publishing to the catalog

In the plugins repo: add the plugin's folder (a Swift package on IslandKit, or a Go module whose program prints its plugin.json with `--describe`) and open a pull request. CI tests IslandKit and builds every plugin; on `main` it releases each new version universal (arm64 and x86_64), ad-hoc signed, as the GitHub release `<id>-<version>` with the zip attached, and updates `index.json` with the checksum, size, author and homepage. Bump `version` to publish an update; the id can't change once published. The CI is `island-plugin build --all` and `publish`, both in `IslandKit/Sources/island-plugin`; `PluginPackage` there is where a folder's kind (Swift or Go) is told apart and built, and where another language would be added.
