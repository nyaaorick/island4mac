# Changelog

What changed in each release, newest first, for users. Every release adds its section before it is published: `Release.command --publish` uses it as the release notes and refuses a version without one (`spec/skills/release`).

## Unreleased

- The app is called island4mac everywhere now (the menu bar, Settings, permissions), with a new bundle id: a 1.1.0 copy doesn't update itself to this version, so install it from the DMG once and grant Accessibility and Automation again; your plugins and their data move over
- Settings > Plugins is a hub: installed plugins show their version, status, a switch, an Update button and a menu (Finder, data folder, homepage, uninstall); Update All; the catalog's plugins with description, author and size, a search field, and the install's progress; Install from File takes a plugin's zip or folder from your Mac; the catalog is kept so the pane shows at once and offline; the Plugins item in the sidebar counts the updates; Advanced has the catalog's address
- Downloads are checked against the catalog's checksum before they are installed
- A plugin that runs on demand shows what it last showed right after launch, without running
- Clipboard and Music settings show their choices by name ("A week", "NetEase Cloud Music")
- Removed settings that did nothing: menu bar icon, window shadow, lighting effect, gradient background, colored spectrum, control slots, progress bar color, settings icon in the island, idle face, remember last tab

## 1.1.0

First release on GitHub.

- Music, Agents, Clipboard and Files in the notch, in black or Liquid Glass, with plugins for more
- Installs from a DMG, and checks for a newer release each time it starts and offers to install it
