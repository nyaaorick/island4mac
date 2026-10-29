# CLAUDE.md

island4mac: a macOS menu bar app (Swift, SwiftUI + AppKit, macOS 26) that turns the MacBook notch into a Dynamic Island, and a hub for the plugins that fill it.

Everything that is not code lives in `spec/`: the design documents under `spec/docs/` and the Claude Code skills under `spec/skills/` (`.claude/skills` points there). Start with `spec/README.md`, which lists them and the conventions. The three rules that are never bent:

- English only, Swift only (the two helpers too), no third-party dependencies.
- The bundle id `com.nyaaorick.island4mac` and the release certificate never change once a release has users: the signature ties installed copies' updates and permissions to them (`spec/docs/06-dev-builds-and-releases.md`).
- A plugin says what to show, never how. Anything a plugin needs from the island goes through the protocol, so every plugin gets it (`spec/docs/04-plugin-protocol.md`).

Build and test: `spec/skills/island4mac-workflow/SKILL.md`.
