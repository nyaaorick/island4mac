---
name: island4mac-workflow
description: Working rules for any change to island4mac; read before touching code, tests, the project or spec.
---

# island4mac essentials

- **Read the spec first.** `spec/docs/01-goals.md` says what this is; `03-architecture.md` where things are and what is easy to break; `04-plugin-protocol.md` before anything a plugin sees; `07-roadmap.md` what is open.
- **Rules that never bend:** English only (code, comments, strings, fixtures; `en.lproj` is the only localization, read through `L("key")`). Swift only, including `Helpers/` and the two `.command` scripts. No third-party dependencies. The bundle id `com.nyaaorick.island4mac` and the release certificate never change. A plugin says what to show, never how.
- **Delete rather than keep.** No settings without an effect, no migrations from versions nobody runs, no commented-out code, no "fix" markers in comments. A comment says why, not what the next line does. Git history is the archive.
- **Identity decides storage.** Anything new the app stores goes under the bundle id or `BuildConfig.supportFolder`, never a fixed name both the dev app and the release would share (`06-dev-builds-and-releases.md`).
- **Folders are synced with Xcode.** Add, move or delete files on disk under `island4mac/`, `island4macTests/`, `SharedCore/`, `BundledPlugins/*/Sources` and `Core/`; no project edits for that. A new target or copy phase is a project edit.
- **One main type per file,** named after it. Suffixes: Store, Service, Client, Monitor, Controller (`03-architecture.md`, "Conventions").
- **Logging** is `Logger(subsystem: Log.subsystem, category:)`; never `print`.

## Build and test

```sh
xcodebuild -project island4mac.xcodeproj -scheme island4mac -destination 'platform=macOS' build
xcodebuild -project island4mac.xcodeproj -scheme island4mac -destination 'platform=macOS' test
```

Needs Xcode 26 and `../island4mac-plugins` beside this repo (IslandKit is a local package). `Launch.command` builds and opens the dev app. Tests take about 40 s after the build; they are hosted by the dev app and skip its launch setup. Run the whole suite before saying a change is done, and read the failures: many tests drive real processes (`/bin/sh` plugins) and real folders, so a failure is usually real.

## Where a change goes

| Change | Place |
| --- | --- |
| How the island opens, sizes, animates, draws | `island4mac/Island/` and `03-architecture.md`, "The island" |
| What a plugin can send or receive | `spec/skills/plugin-protocol-change/SKILL.md` |
| How plugins are found, installed, updated | `island4mac/Plugins/Catalog/` and `05-plugin-hub.md` |
| A bundled plugin | `spec/skills/bundled-plugin/SKILL.md` |
| A setting | `SettingsDefaults` (a key with a reader), the pane in `Settings/`, a string in `Localizable.strings` if reused |
| macOS integration | `island4mac/System/` |
| Something users see changed | `spec/docs/08-changelog.md` under the next version |
