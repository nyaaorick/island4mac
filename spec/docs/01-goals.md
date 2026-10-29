# Goals

## What island4mac is

A macOS menu bar app that turns the MacBook notch into a Dynamic Island: the collapsed island shows one live thing beside the camera (what plays, an agent at work, a plugin's countdown), and the open island shows up to six tabs. The app itself draws everything; what fills the tabs comes from plugins, four of which ship in the app (Music, Clipboard, Files, Agents) and the rest from a catalog or the user's own folder.

island4mac is therefore two things: an island, and a hub for the programs that fill it.

## Principles

1. **A plugin says what to show, never how.** The protocol carries rows, cards, a compact line, a player, buttons, a text field, popups and states; it carries no colors, fonts or layout. Every plugin looks like the rest of the island, and a plugin written for protocol 1 still runs today.
2. **Out of process.** A plugin is a program the island runs and talks to over its stdin and stdout. Nothing third-party loads into the app, the Hardened Runtime stays on, and a plugin that crashes takes nothing with it.
3. **One identity, forever.** The bundle id `com.nyaaorick.island4mac` (changed from `com.macdynamicisland.app` on 2026-10-29, while no release had users) and the self-signed release certificate never change from here on: installed copies take only updates signed like themselves, and macOS ties the Accessibility and Automation permissions to that identity.
4. **The dev app never touches the release.** Every Debug build is a separate app with its own settings, folders, permissions and agent hooks, and the installed release steps aside while it runs.
5. **No third-party dependencies.** Swift and the system frameworks only, including the release and update tooling.
6. **English only, Swift only.** Code, comments, strings and the two helper programs. The only localization is `en.lproj`.
7. **Delete rather than keep.** A setting with no effect, a migration from a version nobody runs, a comment that narrates a fix: gone. Git history is the archive.

## What it is not

- Not sandboxed, and not on the App Store: MediaRemote and AppleScript need the former, and there is no paid developer account for the latter.
- Not a theme engine: two themes (black, Liquid Glass), one background color menu, one corner radius slider.
- Not a plugin UI toolkit. A plugin that needs more than the protocol offers asks for the protocol to grow (spec/skills/plugin-protocol-change), not for a way around it.
