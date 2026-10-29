---
name: bundled-plugin
description: Changing or adding one of the plugins that ship in the app (agents, clipboard, files, music).
---

# Bundled plugins

They are ordinary IslandKit plugins in `BundledPlugins/<id>/`: `Sources/<Name>Plugin.swift` (the thin `IslandPlugin`: what it shows, its preferences, taps) and `Core/` (its logic: stores, clients, monitors; no SwiftUI, Settings or island types). `Core/` is compiled into the plugin and into the app, so `island4macTests` covers it. `plugin.json` is written by the program, never by hand. Background: `spec/docs/05-plugin-hub.md`, "Bundled plugins".

## Changing one

1. Edit `Sources/` or `Core/`. Build and run the app (Xcode or `Launch.command`): the plugin targets build with it.
2. If anything that ends up in `plugin.json` changed (id, name, symbol, version, description, a `@Preference`, `background`, `priority`, `lifecycle`, `acceptsDrops`, or what `body` shows), write it again:
   ```sh
   build/Build/Products/Debug/island4mac.app/Contents/Helpers/<id> --describe > BundledPlugins/<id>/plugin.json
   ```
   `PluginTests.testEachBundledPluginDescribesItselfAsItsPluginJSON` fails until it matches.
3. Run the tests.

## When it needs something new from the island

Follow `spec/skills/plugin-protocol-change/SKILL.md`: the app first, then IslandKit, then the plugin. Never reach around the protocol.

## Adding one

1. Write it as an IslandKit plugin in `BundledPlugins/<id>/`, logic in `Core/`.
2. In Xcode, add a macOS Command Line Tool target whose product is named after the id. Give it IslandKit, its `Sources/` and `Core/` folders and `SharedCore/`. Add `Core/` to the app target too.
3. In the app target: depend on the new target, add its product to **Embed Helpers** (`Contents/Helpers`), and add a copy phase **Embed Bundled Plugin `<id>`** that copies its `plugin.json` to Resources at `Plugins/<id>`.
4. If it replaces a built-in tab, add it to `IslandTab.builtInTabsOfPlugins`.
5. Write its `plugin.json` with `--describe`, and run the tests.
