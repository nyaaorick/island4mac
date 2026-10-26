# island4mac

A macOS menu bar app that turns the MacBook notch into a "Dynamic Island".

## Features

- **Music**: now playing with artwork, playback controls and synced lyrics
- **Agents**: live progress from Claude Code, Codex and ZCode, and answers to their permission prompts right in the island
- **Clipboard**: clipboard history
- **Files**: a drag-and-drop file shelf
- **Themes**: solid black, or Liquid Glass like Control Center
- **Tabs and plugins**: pick up to 6 tabs; Music, Clipboard, Files and Agents are plugins that ship in the app, and plugins add more. Write your own with IslandKit, the Swift SDK in [island4mac-plugins](https://github.com/nyaaorick/island4mac-plugins) ([guide](https://github.com/nyaaorick/island4mac-plugins#writing-a-plugin-with-islandkit), [protocol](https://github.com/nyaaorick/island4mac-plugins#the-protocol))

## Install

Requires macOS 26.0 or later. Download [island4mac.dmg](https://github.com/nyaaorick/island4mac/releases/latest/download/island4mac.dmg), open it and drag the app into Applications.

The app isn't notarized by Apple, so the first time you open it macOS says it can't verify it. Click Done, then open System Settings > Privacy & Security and click Open Anyway beside "MacDynamicIsland" (or run `xattr -dr com.apple.quarantine /Applications/MacDynamicIsland.app` once). After that it opens normally. When asked, grant Accessibility (hotkeys, full-screen detection) and Automation (lyrics, paste, terminal focus).

Each time it starts, the app checks for a newer release and offers to install it. What changed: [CHANGELOG.md](CHANGELOG.md).

## Build from source

Requires Xcode 26. Double-click `Launch.command` in Finder. It builds the app into `build/` and opens it.

Or open `MacDynamicIsland.xcodeproj` in Xcode and run the `MacDynamicIsland` scheme.

Either way you get "Mac Dynamic Island Dev", a separate app from an installed copy, with its own settings, data and permissions. While it runs, the installed copy steps aside, and it comes back when the dev build quits.

## Shortcuts

| Shortcut | Action |
|---|---|
| ⇧⌘Space | Open or close the island |
| ⌥⌘Space | Show or hide the island |
| ⌥⌘V | Open the clipboard tab |

A two-finger swipe on the island also opens and closes it.

## Credits

Developed by [nyaaorick](https://github.com/nyaaorick). Forked from [mac-dynamic-island](https://github.com/RayTracingON/mac-dynamic-island) and based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

See `CLAUDE.md` for build and test commands and an overview of the code.
