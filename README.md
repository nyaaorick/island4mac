# island4mac

A macOS menu bar app that turns the MacBook notch into a Dynamic Island, and a hub for the plugins that fill it.

- **Music**: now playing with artwork, playback controls and synced lyrics
- **Agents**: live progress from Claude Code, Codex and ZCode, and their permission prompts answered right in the island
- **Clipboard**: clipboard history
- **Files**: a drag-and-drop file shelf
- **Themes**: solid black, or Liquid Glass like Control Center
- **Plugins**: pick up to 6 tabs. Music, Clipboard, Files and Agents are plugins that ship in the app; Settings > Plugins installs more from the [plugin catalog](https://github.com/nyaaorick/island4mac-plugins), updates them, and takes a plugin's zip from your Mac. Write your own with IslandKit, the Swift SDK, or in any language with the [protocol](spec/docs/04-plugin-protocol.md).

## Install

Requires macOS 26.0 or later. Download [island4mac.dmg](https://github.com/nyaaorick/island4mac/releases/latest/download/island4mac.dmg), open it and drag the app into Applications.

The app isn't notarized by Apple, so the first time you open it macOS says it can't verify it. Click Done, then open System Settings > Privacy & Security and click Open Anyway beside "island4mac" (or run `xattr -dr com.apple.quarantine /Applications/island4mac.app` once). After that it opens normally. When asked, grant Accessibility (hotkeys, full-screen detection) and Automation (lyrics, paste, terminal focus).

Each time it starts, the app checks for a newer release and offers to install it. Coming from 1.1.0 (MacDynamicIsland): install this version from the DMG once, since its identity changed, and grant the permissions again; your plugins and data move over. What changed: [spec/docs/08-changelog.md](spec/docs/08-changelog.md).

## Shortcuts

| Shortcut | Action |
|---|---|
| ⇧⌘Space | Open or close the island |
| ⌥⌘Space | Show or hide the island |
| ⌥⌘V | Open the clipboard tab |

A two-finger swipe on the island also opens and closes it.

## Build from source

Requires Xcode 26 and the plugins repo cloned beside this one (`../island4mac-plugins`, for IslandKit). Double-click `Launch.command`: it builds the dev app into `build/` and opens it. Or open `island4mac.xcodeproj` and run the `island4mac` scheme. Design and working notes: [spec/](spec/README.md).

## Credits

By [nyaaorick](https://github.com/nyaaorick). The island's window physics, drag detection and now-playing approach come from [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0), by way of [mac-dynamic-island](https://github.com/RayTracingON/mac-dynamic-island).
