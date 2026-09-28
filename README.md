# island4mac

A macOS menu bar app that turns the MacBook notch into a "Dynamic Island".

## Features

- **Music**: now playing with artwork, playback controls and synced lyrics
- **Agents**: live progress from Claude Code, Codex and ZCode, and answers to their permission prompts right in the island
- **Clipboard**: clipboard history
- **Files**: a drag-and-drop file shelf
- **Themes**: solid black, or Liquid Glass like Control Center

## Requirements

- macOS 26.0 or later
- Xcode 26

## Run it

Double-click `Launch.command` in Finder. It builds the app into `build/` and opens it.

Or open `MacDynamicIsland.xcodeproj` in Xcode and run the `MacDynamicIsland` scheme.

When asked, grant Accessibility (hotkeys, full-screen detection) and Automation (lyrics, paste, terminal focus).

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
