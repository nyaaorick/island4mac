---
name: plugin-protocol-change
description: How to add something to the plugin protocol or IslandKit so every plugin, the app, the docs and the tests move together.
---

# Changing the protocol

The protocol is documented once, in `spec/docs/04-plugin-protocol.md`. The app reads it in `island4mac/Plugins/Protocol/`; IslandKit (plugins repo, `IslandKit/Sources/IslandKit/`) speaks it; the bundled plugins use IslandKit.

## Does it need a new version?

A protocol version is bumped only when an older app would do the wrong thing with the new message or field. A field an older app ignores (a new optional key, an unknown `state`) doesn't need one; a message an older app would run unasked (an action with `confirm`) does, and IslandKit then leaves it out on older islands rather than send it. Write that decision into the "Versions" table.

## Steps, in order

1. **The app.** `PluginMessage` / `PluginEvent` (or `PluginManifest` for a plugin.json field), the view that draws it under `Plugins/Views/`, and `PluginManifest.supportedProtocol` if the version grows. Keep decoding lenient: an unknown value reads as none, not as a failed message. Add the decode test to `island4macTests/PluginTests.swift` ("every kind of message reads").
2. **IslandKit.** The element or API in `Elements.swift`, `Wire.swift` and `IslandRuntime.swift`; `PluginDescription` if the plugin.json gains a field or the oldest version a `body` needs changes; a test in `IslandKit/Tests/IslandKitTests/`. `swift test` in the plugins repo.
3. **The docs.** `04-plugin-protocol.md` (the table and the Versions row), the plugins repo's README (the IslandKit element table and the "Which app versions it needs" table). The README teaches IslandKit and links to the protocol document; don't duplicate the wire format there.
4. **The bundled plugins**, if one wants it, and their `plugin.json` written again with `--describe` (`spec/skills/bundled-plugin/SKILL.md`).
5. **The catalog**, if `plugin.json` or `index.json` gained a field: `PluginCatalogEntry`, `PublishCommand.Entry`, `05-plugin-hub.md`.

The plugin must stay a plugin: it reaches the island only through the protocol, so the same feature works for anyone's plugin.
